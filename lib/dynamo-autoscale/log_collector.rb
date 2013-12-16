module DynamoAutoscale
  class LogCollector < ::Logger
    attr_reader :messages

    def initialize log_to
      super

      @messages = Hash.new { |h, k| h[k] = [] }
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method level do |message|
        @messages[level] << message
        super message
      end
    end
  end
end
