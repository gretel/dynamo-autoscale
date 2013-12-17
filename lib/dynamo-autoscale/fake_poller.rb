module DynamoAutoscale
  # This class allows you to specify exactly what data to send through the
  # poller.
  #
  # Example:
  #
  #   DynamoAutoscale.poller_class = FakePoller
  #   DynamoAutoscale.poller_opts  = {
  #     data: {
  #       Time.now => {
  #         provisioned_reads:  100,
  #         provisioned_writes: 100,
  #         consumed_reads:     55.6,
  #         consumed_writes:    12.7,
  #       },
  #       Time.now + 15.minutes => {
  #         provisioned_reads:  100,
  #         provisioned_writes: 100,
  #         consumed_reads:     45.9,
  #         consumed_writes:    7.1,
  #       },
  #     }
  #   }
  class FakePoller < Poller
    def initialize *args
      super(*args)
      opts = args.last.is_a?(Hash) ? args.last : {}

      @data = opts[:data]
    end

    def poll tables, &block
      @data.each do |key, value|
        tables.each do |table_name|
          block.call(table_name, key => value)
        end
      end
    end
  end
end
