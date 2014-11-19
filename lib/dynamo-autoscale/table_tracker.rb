require 'csv'
require 'json'
require 'rbtree'
require 'tempfile'

module DynamoAutoscale
  class TableTracker
    include DynamoAutoscale::Logger

    # TODO: abstraction
    TIME_WINDOW = 7.days

    attr_reader :name, :data, :triggered_rules, :scale_events

    def initialize name
      @name = name
      clear_data
    end

    def clear_data
      @data            = RBTree.new
      @triggered_rules = RBTree.new
      @scale_events    = RBTree.new
    end

    # `tick` takes two arguments. The first is a Time object, the second is
    # a hash. The tick method expects data in the following format for the
    # second argument:
    #
    #   {:provisioned_writes=>600.0,
    #    :provisioned_reads=>800.0,
    #    :consumed_writes=>52.693333333333335,
    #    :consumed_reads=>342.4033333333333}
    def tick time, datum
      if time < (Time.now.utc - TIME_WINDOW)
        logger.warn '[table_tracker] Attempted to insert data outside of the time window.'
        return
      end

      # Sometimes there are gaps in the data pertaining to provisioned
      # amounts. These two conditional blocks fill in those gaps.
      if datum[:provisioned_writes].nil?
        datum[:provisioned_writes] = last_provisioned_for :writes, at: time

        if datum[:provisioned_writes]
          logger.debug '[table_tracker] Filled gap in provisioned writes.'
        end
      end
      if datum[:provisioned_reads].nil?
        datum[:provisioned_reads] = last_provisioned_for :reads, at: time

        if datum[:provisioned_reads]
          logger.debug '[table_tracker] Filled gap in provisioned reads.'
        end
      end

      @data[time] = datum
      remove_expired_data! @data
      remove_expired_data! @triggered_rules
      remove_expired_data! @scale_events
    end

    # Gets the last amount of provisioned throughput for whatever metric you
    # pass in. Example:
    #
    #   table.last_provisioned_for :writes
    #   #=> 600.0
    def last_provisioned_for metric, opts = {}
      key = case metric
      when :reads, :provisioned_reads, :consumed_reads
        :provisioned_reads
      when :writes, :provisioned_writes, :consumed_writes
        :provisioned_writes
      end

      @data.reverse_each do |time, datum|
        if opts[:at].nil? or time <= opts[:at]
          return datum[key] if datum[key]
        end
      end

      return nil
    end

    # Gets the last amount of consumed throughput for whatever metric you
    # pass in. Example:
    #
    #   table.last_consumed_for :writes
    #   #=> 54.3456
    def last_consumed_for metric, opts = {}
      key = case metric
      when :reads, :provisioned_reads, :consumed_reads
        :consumed_reads
      when :writes, :provisioned_writes, :consumed_writes
        :consumed_writes
      end

      @data.reverse_each do |time, datum|
        if opts[:at].nil? or time <= opts[:at]
          return datum[key] if datum[key]
        end
      end

      return nil
    end

    # Useful method for querying the last N points, or the last points in a
    # time range. For example:
    #
    #    table.last 5. :consumed_writes
    #    #=> [ array of last 5 data points ]
    #
    #    table.last 5.minutes, :provisioned_reads
    #    #=> [ array containing the last 5 minutes of provisioned read data ]
    #
    # If there are no points present, or no points in your time range, the
    # return value will be an empty array.
    def last value, metric
      if value.is_a? ActiveSupport::Duration
        value = value.to_i
        to_return = []
        now = Time.now.to_i

        @data.reverse_each do |time, datum|
          value -= now - time.to_i
          now    = time.to_i
          break if value < 0

          to_return << datum[metric]
        end

        to_return
      else
        @data.reverse_each.take(value).map { |time, datum| datum[metric] }
      end
    end

    # Calculate how many read units have been wasted in the current set of
    # tracked data.
    #
    #   table.wasted_read_units
    #   #=> 244.4
    def wasted_read_units
      @data.inject(0) do |memo, (_, datum)|
        # if datum[:provisioned_reads] and datum[:consumed_reads]
          memo += datum[:provisioned_reads] - datum[:consumed_reads]
        # end

        memo
      end
    end

    # Calculate how many write units have been wasted in the current set of
    # tracked data.
    #
    #   table.wasted_write_units
    #   #=> 566.3
    def wasted_write_units
      @data.inject(0) do |memo, (_, datum)|
        # if datum[:provisioned_writes] and datum[:consumed_writes]
          memo += datum[:provisioned_writes] - datum[:consumed_writes]
        # end

        memo
      end
    end

    # Whenever the consumed units goes above the provisioned, we refer to the
    # overflow as "lost" units.
    def lost_read_units
      @data.inject(0) do |memo, (_, datum)|
        if datum[:consumed_reads] > datum[:provisioned_reads]
          memo += datum[:consumed_reads] - datum[:provisioned_reads]
        end

        memo
      end
    end

    # Whenever the consumed units goes above the provisioned, we refer to the
    # overflow as "lost" units.
    def lost_write_units
      @data.inject(0) do |memo, (_, datum)|
        if datum[:consumed_writes] > datum[:provisioned_writes]
          memo += datum[:consumed_writes] - datum[:provisioned_writes]
        end

        memo
      end
    end

    def total_read_units
      @data.inject(0) do |memo, (_, datum)|
        memo += datum[:provisioned_reads] if datum[:provisioned_reads]
        memo
      end
    end

    def total_write_units
      @data.inject(0) do |memo, (_, datum)|
        memo += datum[:provisioned_writes] if datum[:provisioned_writes]
        memo
      end
    end

    def wasted_write_cost
      UnitCost.write(wasted_write_units)
    end

    def wasted_read_cost
      UnitCost.read(wasted_read_units)
    end

    def lost_write_cost
      UnitCost.write(lost_write_units)
    end

    def lost_read_cost
      UnitCost.read(lost_read_units)
    end

    def total_write_cost
      UnitCost.write(total_write_units)
    end

    def total_read_cost
      UnitCost.read(total_read_units)
    end

    def wasted_read_percent
      (wasted_read_units / total_read_units) * 100.0
    end

    def wasted_write_percent
      (wasted_write_units / total_write_units) * 100.0
    end

    def lost_write_percent
      (lost_write_units / total_write_units) * 100.0
    end

    def lost_read_percent
      (lost_read_units / total_read_units) * 100.0
    end

    # Returns an array of all of the time points that have data present in
    # them. Example:
    #
    #    table.tick(Time.now, { ... })
    #    table.tick(Time.now, { ... })
    #
    #    table.all_times
    #    #=> Array with the 2 time values above in it
    def all_times
      @data.keys
    end

    # Returns the earliest point in time that we have tracked data for.
    def earliest_data_time
      all_times.first
    end

    # Returns the latest point in time that we have tracked data for.
    def latest_data_time
      all_times.last
    end

    # Pricing is pretty difficult. This isn't a good measure of success. Base
    # calculations on how many units are wasted.
    # def wasted_money
    #   UnitCost.read(wasted_read_units) + UnitCost.write(wasted_write_units)
    # end

    def to_csv!
      path = DynamoAutoscale.data_dir("#{self.name}.csv")

      CSV.open(path, 'w') do |csv|
        csv << [
          "time",
          "provisioned_reads",
          "provisioned_writes",
          "consumed_reads",
          "consumed_writes",
        ]

        @data.each do |time, datum|
          csv << [
            time.iso8601,
            datum[:provisioned_reads],
            datum[:provisioned_writes],
            datum[:consumed_reads],
            datum[:consumed_writes],
          ]
        end
      end
      DynamoAutoscale.logger.debug "[table_tracker] Dumped CSV file to: #{path}"
      path
    end

    def graph!(r_script = 'dynamodb_graph.r')
      csv_file = to_csv!
      output_file = csv_file + '.png'
      script_file = DynamoAutoscale.rlib_dir(r_script)

      path = do_graph!(csv_file: csv_file,
                         output_file: output_file,
                         r_file: script_file)
      DynamoAutoscale.logger.info "[table_tracker] Saved graph file to: #{path}"
      path
    end

    def report! opts = {}
      opts[:metric] ||= :units

      unless [:cost, :units].include?(opts[:metric])
        raise ArgumentError.new('The :metric option must be one of :cost or ' +
          ':units')
      end

      if opts[:metric] == :units
        STDERR.puts "         Table: #{name}"
        STDERR.puts "Wasted r/units: #{wasted_read_units.round(2)} (#{wasted_read_percent.round(2)}%)"
        STDERR.puts " Total r/units: #{total_read_units.round(2)}"
        STDERR.puts "  Lost r/units: #{lost_read_units.round(2)} (#{lost_read_percent.round(2)}%)"
        STDERR.puts "Wasted w/units: #{wasted_write_units.round(2)} (#{wasted_write_percent.round(2)}%)"
        STDERR.puts " Total w/units: #{total_write_units.round(2)}"
        STDERR.puts "  Lost w/units: #{lost_write_units.round(2)} (#{lost_write_percent.round(2)}%)"
        STDERR.puts "      Upscales: #{DynamoAutoscale.actioners[self].upscales}"
        STDERR.puts "    Downscales: #{DynamoAutoscale.actioners[self].downscales}"
      elsif opts[:metric] == :cost
        STDERR.puts "         Table: #{name}"
        STDERR.puts "Wasted r/cost: $#{wasted_read_cost.round(2)} (#{wasted_read_percent.round(2)}%)"
        STDERR.puts " Total r/cost: $#{total_read_cost.round(2)}"
        STDERR.puts "  Lost r/cost: $#{lost_read_cost.round(2)} (#{lost_read_percent.round(2)}%)"
        STDERR.puts "Wasted w/cost: $#{wasted_write_cost.round(2)} (#{wasted_write_percent.round(2)}%)"
        STDERR.puts " Total w/cost: $#{total_write_cost.round(2)}"
        STDERR.puts "  Lost w/cost: $#{lost_write_cost.round(2)} (#{lost_write_percent.round(2)}%)"
        STDERR.puts "      Upscales: #{DynamoAutoscale.actioners[self].upscales}"
        STDERR.puts "    Downscales: #{DynamoAutoscale.actioners[self].downscales}"
      end
    end

    private

    # Helper function which wraps around the call of the graphing tool
    def do_graph! opts = {}
      begin
        # TODO: be platform agnostic
        raise unless system "R --no-save --args #{opts[:csv_file]} #{opts[:output_file]} < #{opts[:r_file]}"
      rescue => e
        logger.error "[table_tracker] Exception: #{e.inspect}"
        return nil
      end
      return opts[:output_file]
    end

    # Helper function to remove data from an RBTree object keyed on a Time
    # object where the key is outside of the time window defined by the
    # TIME_WINDOW constant.
    def remove_expired_data! data
      # logger.debug "[table_tracker] Pruning data that may be out of time window..."
      now = Time.now.utc
      to_delete = data.each.take_while { |key, _| key < (now - TIME_WINDOW) }
      to_delete.each { |key, _| data.delete(key) }
    end
  end
end
