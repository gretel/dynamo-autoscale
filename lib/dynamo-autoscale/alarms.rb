module DynamoAutoscale
  class Alarms
    include DynamoAutoscale::Logger

    # Updates the thresholds of the read/write capacity alarms for a table in DynamoDB.
    #
    # Example:
    #
    #   pp DynamoAutoscale::Alarms.update_alarms("table_name")
    #   #=> {
    #       :previous_reads => value,
    #       :previous_writes => value,
    #       :new_reads => value,
    #       :new_writes => value,
    #       }
    def self.update_alarms table_name, data = {}
      if data[:new_reads] && data[:previous_reads] != data[:new_reads]
        update_metric_alarms(table_name, 'ConsumedReadCapacityUnits', data[:new_reads].to_f / data[:previous_reads])
      end

      if data[:new_writes] && data[:previous_writes] != data[:new_writes]
        update_metric_alarms(table_name, 'ConsumedWriteCapacityUnits', data[:new_writes].to_f / data[:previous_writes])
      end
    end

    # This method accepts the following arguments:
    #
    #   - :table_name  - The name of the table you would like to update alarm for.
    #   - :metric_name - The name of the metric for the alarm to be updated.
    #   - :scale - This is the scale factor that the new threshold would scale to.
    #   It is a percentage value calculated by dividing the new provisioned capacity
    #   by the last provisioned capacity.
    def self.update_metric_alarms table_name, metric_name, scale
      opts = {
        namespace: 'AWS/DynamoDB',
        metric_name:  metric_name,
        dimensions:  [{ name: "TableName", value: table_name }],
      }
      # Get the array of alarms for the specific metric
      alarms = describe_metric_alarms(opts)
      alarms.each do |alarm|
        # Fill in the required attributes for updating alarm
        update_opts = {
          alarm_name:  alarm[:alarm_name],
          statistic:  alarm[:statistic],
          period:  alarm[:period],
          evaluation_periods:  alarm[:evaluation_periods],
          comparison_operator:  alarm[:comparison_operator],
        }.merge(opts)

        # The only thing we want to update is the threshold
        update_opts[:threshold] = alarm[:threshold] * scale
        logger.info "[alarms] [#{alarm[:alarm_name]}] #{alarm[:threshold]} -> #{update_opts[:threshold]}"
        # Update metric alarm
        client.put_metric_alarm(update_opts)
      end
    end

    # A base method that makes a call to CloudWatch, getting descriptions
    # of alarms on whatever opts is given.
    def self.describe_metric_alarms opts = {}
      client.describe_alarms_for_metric(opts)[:metric_alarms]
    end

    private

    def self.client
      @@client ||= AWS::CloudWatch.new.client
    end
  end
end
