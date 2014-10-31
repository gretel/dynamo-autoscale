if config = DynamoAutoscale.config[:logger]
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

  if config[:style] == "pretty"
    DynamoAutoscale::Logger.logger.formatter = DynamoAutoscale::PrettyFormatter.new
  else
    DynamoAutoscale::Logger.logger.formatter = DynamoAutoscale::StandardFormatter.new
  end

  if config[:level]
    DynamoAutoscale::Logger.logger.level = ::Logger.const_get(config[:level])
  end
end

if ENV['DEBUG']
  DynamoAutoscale::Logger.logger.level = ::Logger::DEBUG
  AWS.config(logger: DynamoAutoscale::Logger.logger)
elsif ENV['SILENT']
  DynamoAutoscale::Logger.logger.level = ::Logger::FATAL
end
