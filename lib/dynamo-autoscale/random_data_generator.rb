module DynamoAutoscale
  class RandomDataGenerator < Poller
    def initialize *args
      super(*args)
      opts = args.last.is_a?(Hash) ? args.last : {}

      @num_points         = opts[:num_points] || 100
      @start_time         = opts[:start_time] || Time.now
      @current_time       = @start_time
      @provisioned_reads  = opts[:provisioned_reads] || 600
      @provisioned_writes = opts[:provisioned_writes] || 600

      srand(@start_time.to_i)
    end

    def poll tables, &block
      # Give each table its initial provisioned reads and writes before starting
      # the random data generation.
      tables.each do |table_name|
        block.call(table_name, {
          provisioned_reads: {
            @start_time => @provisioned_reads,
          },
          provisioned_writes: {
            @start_time => @provisioned_writes,
          },
        })
      end

      @num_points.times do
        tables.each do |table_name|
          # Give each table varying figures for consumed reads and writes that
          # hover between 0 and their provisioned values multiplied by 2.
          block.call(table_name, {
            consumed_reads: {
              @current_time => rand * @provisioned_reads * 2,
            },
            consumed_writes: {
              @current_time => rand * @provisioned_writes * 2,
            },
          })

          @current_time += 15.minutes
        end
      end
    end
  end
end
