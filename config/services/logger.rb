logger_config = DynamoAutoscale.config[:logger]

if logger_config[:sync]
  STDOUT.sync = true
  STDERR.sync = true
end

if logger_config[:log_to]
  STDOUT.reopen(logger_config[:log_to])
  STDERR.reopen(logger_config[:log_to])
end

if RUBY_VERSION.to_i > 1
  require 'mono_logger'
  DynamoAutoscale::Logger.logger = ::MonoLogger.new(STDOUT)
else
  require 'logger'
  DynamoAutoscale::Logger.logger = ::Logger.new(STDOUT)
end

if logger_config[:pretty]
  DynamoAutoscale::Logger.logger.formatter = DynamoAutoscale::PrettyFormatter.new
else
  DynamoAutoscale::Logger.logger.formatter = DynamoAutoscale::StandardFormatter.new
end

if logger_config[:level]
  DynamoAutoscale::Logger.logger.level = ::Logger.const_get(logger_config[:level])
end

if $_DEBUG_LOG
  DynamoAutoscale::Logger.logger.warn 'Debugging output enabled. Not recommended for production use!'
  DynamoAutoscale::Logger.logger.level = ::Logger::DEBUG
  AWS.config(logger: DynamoAutoscale::Logger.logger) if defined? AWS
end
