module DynamoAutoscale
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
