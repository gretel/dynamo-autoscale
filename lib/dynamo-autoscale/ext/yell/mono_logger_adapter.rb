require 'yell'
require 'mono_logger'

class MonoLoggerAdapter < Yell::Adapters::Base
  # Provides us with the :format method
  include Yell::Helpers::Base
  include Yell::Helpers::Formatter

  # Setup is called in your adapters initializer. You are not required to
  # define this method if you have no need for special settings. However, here
  # it's used to initialize the logging class and set the initial message format.
  setup do |options|
    # TODO: abstraction
    @@mono_logger ||= MonoLogger.new(STDOUT)
    self.level = Yell.__fetch__(options, :level)
    self.format = options[:format]
  end

  # Defining write is mandatory. It's the main adapter method and receives the log
  # event. Here, we use the already set `format` (in the setup) to get a pretty
  # message out of the log event.
  write do |event|
    @@mono_logger.log(event.level, format.call(event).strip)
  end
end

# Register the newly written adapter with Yell
Yell::Adapters.register :mono_logger_adapter, MonoLoggerAdapter
