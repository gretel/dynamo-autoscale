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

  module Helpers
    module LoggerHelper
      def catch_logs &block
        old_logger             = DynamoAutoscale.logger
        old_formatter          = old_logger.formatter
        old_level              = old_logger.level
        collector              = LogCollector.new(STDOUT)
        collector.formatter    = old_formatter
        collector.level        = old_level
        DynamoAutoscale.logger = collector

        block.call

        DynamoAutoscale.logger = old_logger
        collector.messages
      end
    end
  end
end
