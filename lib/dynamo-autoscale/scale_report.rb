require 'erb'
require 'pony'

module DynamoAutoscale
  class ScaleReport
    include DynamoAutoscale::Logger

    def initialize(table)
      email_template = File.realpath(DynamoAutoscale.templates_dir(DynamoAutoscale.config[:email_template]))
      raise RuntimeError.new("Email template file '#{email_template}' does not exist") unless File.exists?(email_template)

      @table = table
      @erb = ERB.new(File.read(email_template), nil, '-')

      if DynamoAutoscale.config[:dry_run]
        @enabled = false
      elsif config = DynamoAutoscale.config[:email]
        @enabled = true
        Pony.options = config
      else
        @enabled = false
      end
    end

    def email_subject
      "Scale event for #{@table.name}"
    end

    def email_content
      @erb.result(binding)
    end

    def send
      return false unless @enabled

      result = Pony.mail({
        subject: email_subject,
        body:    email_content,
      })

      if result
        logger.info "[mailer] Mail sent successfully."
        result
      else
        logger.error "[mailer] Failed to send email. Result: #{result.inspect}"
        false
      end
    rescue => e
      logger.error "[mailer] Encountered an error: #{e.class}:#{e.message}"
      false
    end

    def formatted_scale_event(scale_event)
      max_length = max_metric_length(scale_event)

      ['reads', 'writes'].map do |type|
        next unless scale_event.has_key? "#{type}_from".to_sym

        direction = scale_direction( scale_event["#{type}_from".to_sym], scale_event["#{type}_to".to_sym] )
        type_from = scale_event["#{type}_from".to_sym].to_s.rjust(max_length)
        type_to   = scale_event["#{type}_to".to_sym].to_s.rjust(max_length)

        "#{type.capitalize.rjust(6)}: #{direction} from #{type_from} to #{type_to}"
      end.compact
    end

    def max_metric_length(scale_event)
      scale_event.values.max.to_s.length
    end

    def scale_direction(from, to)
      from > to ? 'DOWN' : ' UP '
    end
  end
end
