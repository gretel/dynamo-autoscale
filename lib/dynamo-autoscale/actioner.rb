module DynamoAutoscale
  class Actioner
    include DynamoAutoscale::Logger
    attr_accessor :table, :upscales, :downscales

    # TODO: abstraction
    MAX_DOWNSCALES = 4

    def self.minimum_throughput
      @minimum_throughput ||= 10
    end

    def self.minimum_throughput= new_minimum_throughput
      @minimum_throughput = new_minimum_throughput
    end

    def self.maximum_throughput
      @maximum_throughput ||= 20000
    end

    def self.maximum_throughput= new_maximum_throughput
      @maximum_throughput = new_maximum_throughput
    end

    def initialize table, opts = {}
      @table            = table
      @downscales       = 0
      @upscales         = 0
      @provisioned      = { reads: RBTree.new, writes: RBTree.new }
      @pending          = { reads: nil, writes: nil }
      @last_action      = Time.now.utc
      @last_scale_check = Time.now.utc
      @downscale_warn   = false
      @opts             = opts
    end

    def provisioned_for metric
      @provisioned[normalize_metric(metric)]
    end

    def provisioned_writes
      @provisioned[:writes]
    end

    def provisioned_reads
      @provisioned[:reads]
    end

    def check_day_reset!
      now = Time.now.utc

      if now >= (check = (@last_scale_check + 1.day).midnight)
        logger.info "[actioner] A day has passed. Resetting scaling counts back to zero.."
        # logger.debug "[actioner] Now: #{now}, Comparison: #{check}"
        if @downscales < MAX_DOWNSCALES
          logger.warn "[actioner] Downscales done for last day: #{@downscales} of #{MAX_DOWNSCALES}."
        end

        @upscales = 0
        @downscales = 0
        @downscale_warn = false
      end

      @last_scale_check = now
    end

    # This should be overwritten by deriving classes. In the Dynamo actioner,
    # this should check that the table is in an :active state. In the local
    # actioner this will be faked.
    def can_run?
      false
    end

    def upscales
      check_day_reset!
      @upscales
    end

    def downscales new_val = nil
      check_day_reset!
      @downscales = new_val if new_val
      @downscales
    end

    def set metric, to
      check_day_reset!

      metric = normalize_metric(metric)
      ptime, _ = provisioned_for(metric).last

      # TODO: abstraction
      if ptime and ptime > 2.minutes.ago
        logger.warn "[actioner] [#{metric}] Scaling is allowed every two minutes, skipping."
        return false
      end

      from = table.last_provisioned_for(metric)

      if from and to > (from * 2)
        to = from * 2

        logger.warn "[actioner] [#{metric}] Attempted to scale up more than allowed. Capped scale to #{to.round(2)}."
      end

      if to < Actioner.minimum_throughput
        to = Actioner.minimum_throughput

        logger.warn "[actioner] [#{metric}] Attempted to scale down to less than minimum throughput. Capped scale to #{to.round(2)}."
      end

      if to > Actioner.maximum_throughput
        to = Actioner.maximum_throughput

        logger.warn "[actioner] [#{metric}] Attempted to scale up to greater than maximum throughput. Capped scale to #{to.round(2)}."
      end

      if from and from == to
        logger.debug "[actioner] [#{metric}] Value has not changed. Ignoring..."
        return false
      end

      if from and from > to
        downscale metric, from, to
      else
        upscale metric, from, to
      end
    end

    def upscale metric, from, to
      logger.info "[actioner] [#{metric}] Scaling UP: #{from ? from.round(2) : "Unknown"} -> #{to.round(2)}"

      now = Time.now.utc

      # Because upscales are not limited, we don't need to queue this operation.
      if result = scale(metric, to)
        table.scale_events[now] = {
          "#{metric}_to".to_sym => to,
          "#{metric}_from".to_sym => from,
        }
        @provisioned[metric][now] = to
        @upscales += 1

        ScaleReport.new(table).send unless DynamoAutoscale.config[:email].nil?
      end

      return result
    end

    def downscale metric, from, to
      if @downscales >= MAX_DOWNSCALES
        unless @downscale_warn
          @downscale_warn = true
          logger.error "[actioner] [#{metric}] Scaling failed: Limits reached for today."
        end
        return false
      end

      if @pending[metric]
        logger.info "[actioner] [#{metric}] Scaling DOWN: #{@pending[metric]} -> #{to.round(2)} (writes pending!)"
      else
        logger.info "[actioner] [#{metric}] Scaling DOWN: #{from ? from.round(2) : "Unknown"} -> #{to.round(2)}"
      end
      queue_operation! metric, from, to
    end

    def queue_operation! metric, from, to
      @pending[metric] = [from, to]
      try_flush!
    end

    def try_flush!
      if should_flush?
        if flush_operations!
          @downscales += 1
          @last_action = Time.now.utc
          return true
        else
          return false
        end
      else
        return false
      end
    end

    def flush_operations!
      result = nil
      now = Time.now.utc

      if @pending[:writes] and @pending[:reads]
        wfrom, wto = @pending[:writes]
        rfrom, rto = @pending[:reads]

        if result = scale_both(rto, wto)
          @provisioned[:writes][now] = wto
          @provisioned[:reads][now] = rto

          table.scale_events[now] = {
            writes_from: wfrom,
            writes_to:   wto,
            reads_from:  rfrom,
            reads_to:    rto,
          }

          @pending[:writes] = nil
          @pending[:reads] = nil

          logger.debug "[actioner] Flushed a read and a write event."
        else
          logger.error "[actioner] Failed to flush a read and write event."
        end
      elsif @pending[:writes]
        from, to = @pending[:writes]

        if result = scale(:writes, to)
          @provisioned[:writes][now] = to
          table.scale_events[now]    = { writes_from: from, writes_to: to }
          @pending[:writes]          = nil

          logger.debug "[actioner] Flushed a write event."
        else
          logger.error "[actioner] Failed to flush a write event."
        end
      elsif @pending[:reads]
        from, to = @pending[:reads]

        if result = scale(:reads, to)
          @provisioned[:reads][now] = to
          table.scale_events[now]   = { reads_from: from, reads_to: to }
          @pending[:reads]          = nil

          logger.debug "[actioner] Flushed a read event."
        else
          logger.error "[actioner] Failed to flush a read event."
        end
      end

      return result
    end

    def pending_reads?
      !!@pending[:reads]
    end

    def pending_writes?
      !!@pending[:writes]
    end

    def clear_pending!
      @pending[:writes] = nil
      @pending[:reads] = nil
    end

    def should_flush?
      if @opts[:group_downscales].nil?
        logger.debug "[actioner] Downscales are not being grouped. Should flush..."
        return true
      end

      if pending_reads? and pending_writes?
        logger.debug "[actioner] Both a read and a write operation are pending. Should flush..."
        return true
      end

      now = Time.now.utc

      # I know what you're thinking. How would the last action ever be in the
      # future? Locally, we use Timecop to fake out the time. Unfortunately it
      # doesn't kick in until after the first data point, so when this object is
      # created the @last_action is set to Time.now.utc, then the time gets
      # rolled back, causing the last action to be in the future. This hack
      # fixes that.
      @last_action = now if @last_action > now

      if (@opts[:flush_after] and @last_action and
        (now > @last_action + @opts[:flush_after]))
        logger.debug "[actioner] Flushing, timeout of #{@opts[:flush_after]} reached."
        return true
      end

      logger.debug "[actioner] Flushing conditions not met. Pending operations: " +
        "#{@pending[:reads] ? "1 read" : "no reads"}, " +
        "#{@pending[:writes] ? "1 write" : "no writes"}"

      return false
    end

    private

    def normalize_metric metric
      case metric
      when :reads, :provisioned_reads, :consumed_reads
        :reads
      when :writes, :provisioned_writes, :consumed_writes
        :writes
      end
    end
  end
end
