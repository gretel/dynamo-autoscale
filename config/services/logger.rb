config = DynamoAutoscale.config[:logger]

raise 'missing configuration' unless config

if config[:sync]
  STDOUT.sync = true
  STDERR.sync = true
end

if config[:log_to]
  STDOUT.reopen(config[:log_to])
  STDERR.reopen(config[:log_to])
end

if RUBY_VERSION.to_i > 1
  require 'mono_logger'
  DynamoAutoscale::Logger.logger = ::MonoLogger.new(STDOUT)
else
  require 'logger'
  DynamoAutoscale::Logger.logger = ::Logger.new(STDOUT)
end

if config[:style] == 'pretty'
  DynamoAutoscale::Logger.logger.formatter = DynamoAutoscale::PrettyFormatter.new
else
  DynamoAutoscale::Logger.logger.formatter = DynamoAutoscale::StandardFormatter.new
end

if config[:level]
  DynamoAutoscale::Logger.logger.level = ::Logger.const_get(config[:level])
end

if $_DEBUG_LOG
  DynamoAutoscale::Logger.logger.warn 'Debugging output enabled. Not recommended for production use!'
  DynamoAutoscale::Logger.logger.level = ::Logger::DEBUG
  AWS.config(logger: DynamoAutoscale::Logger.logger) if defined? AWS
end
