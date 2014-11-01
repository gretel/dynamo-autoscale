module DynamoAutoscale
  module Logger
    def self.logger= new_logger
      @@logger = new_logger
    end

    def self.logger
      @@logger ||= DynamoAutoscale::Logger.new(STDOUT)
    end

    def logger
      DynamoAutoscale::Logger.logger
    end

    def logger= new_logger
      DynamoAutoscale::Logger.logger = new_logger
    end

    def self.included base
      base.extend DynamoAutoscale::Logger
    end
  end
end
