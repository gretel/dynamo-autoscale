module DynamoAutoscale
  class StandardFormatter
    def initialize
      @formatter = ::Logger::Formatter.new
    end

    def call(severity, time, progname, msg)
      table = DynamoAutoscale.current_table
      msg   = "[#{table.name}] #{msg}" if table

      @formatter.call(severity, time, progname, msg)
    end
  end

  class PrettyFormatter
    require 'colored'

    def call(severity, time, progname, msg)
      table = DynamoAutoscale.current_table.name rescue "no table"

      "[#{time.utc.to_s.cyan}][#{severity_color(severity)}][#{table.green}] " +
        "#{String === msg ? msg : msg.inspect}\n"
    end

    def severity_color(severity)
      case severity
      when "DEBUG"
        "#{severity}".blue
      when "INFO"
        "#{severity}".white
      when "WARN"
        "#{severity}".yellow
      when "ERROR"
        "#{severity}".red
      when "FATAL"
        "#{severity}".red
      else
        "#{severity}"
      end
    end
  end
end
