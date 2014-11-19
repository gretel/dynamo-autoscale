module DynamoAutoscale
  class DynamoActioner < Actioner
    include DynamoAutoscale::Logger

    def dynamo
      @dynamo ||= AWS::DynamoDB.new.tables[table.name]
    end

    def scale metric, value
      aws_throughput_key = case metric
      when :reads
        :read_capacity_units
      when :writes
        :write_capacity_units
      end

      if throughput_synced?
        dynamo_scale(aws_throughput_key => value)
      else
        # If the throughputs were not synced, the likelihood is we made the
        # decision to scale based on false data. Clear it.
        clear_pending!
        false
      end
    end

    def scale_both reads, writes
      if throughput_synced?
        dynamo_scale(read_capacity_units: reads, write_capacity_units: writes)
      else
        # If the throughputs were not synced, the likelihood is we made the
        # decision to scale based on false data. Clear it.
        clear_pending!
        false
      end
    end

    def can_run?
      dynamo.status == :active
    end

    def throughput_synced?
      time, datum = table.data.last

      # If we've not gathered any data, we cannot know if our values are synced
      # with Dynamo so we have to assume they are not until we get some data in.
      return false if time.nil? or datum.nil?

      if dynamo.read_capacity_units != datum[:provisioned_reads]
        logger.error "[dynamo_actioner] DynamoDB (#{dynamo.read_capacity_units.round(2)}) disagrees" +
          "with CloudWatch (#{datum[:provisioned_reads].round(2)}) on what the provisioned reads are. " +
          "To be on the safe side, operations are not being applied."
        return false
      elsif dynamo.write_capacity_units != datum[:provisioned_writes]
        logger.error "[dynamo_actioner] DynamoDB (#{dynamo.write_capacity_units.round(2)}) disagrees " +
          "with CloudWatch (#{datum[:provisioned_writes].round(2)}) on what the provisioned writes are. " +
          "To be on the safe side, operations are not being applied."
        return false
      end
      return true
    end

    private

    def dynamo_scale opts
      dynamo.provision_throughput(opts)
      # Update alarm as well
      if DynamoAutoscale.config[:update_alarms]
        Alarms.update_alarms(table.name, {
          previous_reads: dynamo.read_capacity_units,
          previous_writes: dynamo.write_capacity_units,
          new_reads: opts[:read_capacity_units],
          new_writes: opts[:write_capacity_units],
        })
      end
      return true
    rescue AWS::DynamoDB::Errors::ValidationException => e
      # When you try to set throughput to a negative value or the same value it
      # was previously you get this.
      logger.warn "[dynamo_actioner] #{e}"
      return false
    rescue AWS::DynamoDB::Errors::ResourceInUseException => e
      # When you try to update a table that is being updated you get this.
      logger.warn "[dynamo_actioner] #{e}"
      return false
    rescue AWS::DynamoDB::Errors::LimitExceededException => e
      # When you try to increase throughput greater than 2x or you try to
      # decrease more than 4 times per day you get this.
      logger.warn "[dynamo_actioner] #{e}"

      aws_description = self.class.describe_table(table)
      decreases_today = aws_description[:provisioned_throughput][:number_of_decreases_today]
      downscales(decreases_today)
      return false
    end

    def self.describe_table table
      client = AWS::DynamoDB::Client.new(:api_version => '2012-08-10')
      data   = client.describe_table(table_name: table.name)
      data[:table]
    end
  end
end
