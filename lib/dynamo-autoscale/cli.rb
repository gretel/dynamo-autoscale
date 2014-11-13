module DynamoAutoscale
  class CLI

    def self.run(name, options)
      require_relative '../../config/environment/common'

      raise RuntimeError.new("Configuration file '#{options.config}' does not exist") unless File.exists?(options.config)

      DynamoAutoscale.setup_from_config(File.realpath(options.config), { :dry_run => options.dry_run ||= true })

      begin
        self.send(name, options)
      rescue RuntimeError => e
        raise e
      end
    end

    private

    def self.start(options)
      DynamoAutoscale.logger.debug "[main] Ensuring tables exist in DynamoDB..."

      dynamo = AWS::DynamoDB.new

      DynamoAutoscale.poller_opts[:tables].select! do |table_name|
        DynamoAutoscale.logger.error "[main] Table '#{table_name}' does not exist inside your DynamoDB." unless dynamo.tables[table_name].exists?
      end

      DynamoAutoscale.poller_class = DynamoAutoscale::CWPoller
      DynamoAutoscale.actioner_class = DynamoAutoscale::DynamoActioner unless DynamoAutoscale.config[:dry_run]
      DynamoAutoscale.logger.debug "[main] Finished setup. Backdating..."
      DynamoAutoscale.poller.backdate

      DynamoAutoscale.logger.info "[main] Polling CloudWatch in a loop..."
      if options.monitor
        require 'timecop'
        DynamoAutoscale.logger.warn "[main] Do not use '--monitor' on production!"
        begin
          DynamoAutoscale.pollerrun
        rescue SignalException, Interrupt => e
          DynamoAutoscale.logger.error "[main] Exception occurred: #{e.class}:#{e.message}"
          Ripl.start :binding => binding
          retry
        rescue => e
          # If we error out, print the error and drop into a repl.
          DynamoAutoscale.logger.error "[main] Exception occurred: #{e.class}:#{e.message}"
          Ripl.start :binding => binding
        end
      else
        DynamoAutoscale.poller.run
      end
    end

    def self.check_email(options)
      table = TableTracker.new("fake_table")

      rulepool = RuleSet.new do
        reads  last: 2, greater_than: "90%", scale: { on: :consumed, by: 1.7 }
        writes last: 2, greater_than: "90%", scale: { on: :consumed, by: 1.7 }
        reads  for:  2.hours, less_than: "20%", min: 10, scale: { on: :consumed, by: 1.8 }
        writes for:  2.hours, less_than: "20%", min: 10, scale: { on: :consumed, by: 1.8 }
      end.rules.values.flatten

      20.times do
        table.tick(rand(1..100).minutes.ago, {
          :provisioned_reads  => rand(1..1000),
          :provisioned_writes => rand(1..1000),
          :consumed_reads     => rand(1..1000),
          :consumed_writes    => rand(1..1000)
        })
      end

      10.times do
        table.triggered_rules[rand(1..100).minutes.ago] = rulepool[rand(rulepool.length)]
      end

      10.times do
        table.scale_events[rand(1..100).minutes.ago] = {
          reads_from:  rand(1..1000),
          reads_to:    rand(1..1000),
          writes_from: rand(1..1000),
          writes_to:   rand(1..1000)
        }
      end

      report = ScaleReport.new(table)
      STDERR.puts "\nSubject: #{report.email_subject}\n#{report.email_content}\n"
      unless report.send
        DynamoAutoscale.logger.error '[main] Error sending mail.'
        exit 1
      end
    end

    def self.check_ruleset(options)
      require_relative 'rule_set'

      begin
        # TODO: check seems flaky!
        DynamoAutoscale::RuleSet.new(DynamoAutoscale.config[:ruleset])
      rescue ArgumentError => e
        STDERR.puts "Ruleset '#{DynamoAutoscale.config[:ruleset]}' has errors!"
        exit 1
      end
      STDERR.puts "Ruleset '#{DynamoAutoscale.config[:ruleset]}' seems OK."
    end

    def self.pull_cw_data(options)
      require 'fileutils'

      # This script will fetch the 6 days of previous data from all of the tables that
      # you have specified in the config passed in as ARGV[0].
      #
      # It will store this data into the `data/` directory of this project in a format
      # that the rest of the tool scripts understands.

      dynamo = AWS::DynamoDB.new
      range  = (Date.today - 5.days).upto(Date.today)
      DynamoAutoscale.logger.info "[main] Date range: #{range.to_a}"

      # Filter out tables that do not exist in Dynamo.
      DynamoAutoscale.poller.tables.select! do |table|
        DynamoAutoscale.logger.error "[main] Table #{table} does not exist, skipping." unless dynamo.tables[table].exists?
      end

      range.each do |start_day|
        dir     = DynamoAutoscale.data_dir(start_day.to_s)
        end_day = start_day + 1.day

        DynamoAutoscale.poller_opts[:tables].each do |table|
          DynamoAutoscale.logger.info "[main] Collecting data for '#{table}' on '#{start_day}'..."
          File.open(File.join(dir, "#{table}.json"), 'w') do |file|
            file.write(JSON.pretty_generate(Metrics.all_metrics(table, {
              period:     5.minutes,
              start_time: start_day,
              end_time:   end_day,
            })))
          end
        end
      end
    end

    def self.lament_wastage(options)
      # This script calculate an approximate "wastage cost" for every table (wastage
      # cost is defined as provisioned throughout - consumed throughput, so throughput
      # that was paid for but not used).

      tables      = AWS::DynamoDB.new.tables.to_a.map(&:name)
      pad         = tables.map(&:length).max
      total_waste = 0
      opts        = { period: 1.hour, start_time: 1.hour.ago, end_time: Time.now }

      tables.each do |table|
        pr = Metrics.provisioned_reads(table, opts).map do |datum|
          datum[:average]
        end.inject(:+) || 0.0

        pw = Metrics.provisioned_writes(table, opts).map do |datum|
          datum[:average]
        end.inject(:+) || 0.0

        cr = Metrics.consumed_reads(table, opts).map do |datum|
          datum[:average]
        end.inject(:+) || 0.0

        cw = Metrics.consumed_writes(table, opts).map do |datum|
          datum[:average]
        end.inject(:+) || 0.0

        waste_cost   = UnitCost.read(pr - cr) + UnitCost.write(pw - cw)
        total_waste += waste_cost

        STDERR.puts "#{table.rjust(pad)}: reads(#{cr.round(4)} / #{pr.round(4)}) " +
             "writes(#{cw.round(4)} / #{pw.round(4)}), ~$#{waste_cost.round(4)} " +
             "wasted per hour"
      end

      STDERR.puts "Total waste cost: ~$#{total_waste.round(4)} per hour"
    end

    def self.test_simulate(options)
      require 'timecop'

      DynamoAutoscale.logger.info "[main] Starting polling loop..."
      # TODO: no data = fail?
      DynamoAutoscale.poller.run do |table, time, datum|
        Timecop.travel(time)

        STDERR.puts "Event at #{time}: #{datum.pretty_inspect}\n"
        STDERR.puts "Press ctrl + d or type 'exit' to step forward in time."
        STDERR.puts "Type 'exit!' to exit entirely."

        Ripl.start :binding => binding
      end
    end

    def self.test_random(options)
      # This script will locally test the tables and options you have specified in
      # your config passed in as ARGV[0].
      #
      # You will first need to have obtained historic data on the tables in your
      # config file. To do this, run:
      #
      #   $ script/historic_data path/to/config.yml
      #
      # This script does not change any throughputs on DynamoDB whatsoever. The
      # historic script data will hit CloudWatch fairly hard to get its data, though.

      require 'timecop'

      # Uncomment this and the below RubyProf lines if you want profiling information.
      # RubyProf.start

      DynamoAutoscale.poller_class = DynamoAutoscale::RandomDataGenerator
      DynamoAutoscale.poller_opts  = {
        num_points: 100,
        start_time: Time.now,
        provisioned_reads: 600,
        provisioned_writes: 600,
      }.merge(DynamoAutoscale.poller_opts)

      begin
        DynamoAutoscale.poller.run { |table_name, time| Timecop.travel(time) }
      rescue Interrupt
        Ripl.start binding: binding
      end

      # Uncomment these and the above RubyProf line if you want profiling information.
      # printer = RubyProf::FlatPrinter.new(RubyProf.stop)
      # printer.print(STDOUT, min_percent: 2)

      # Uncomment this if you want to drop into a REPL at the end of the test.
      # Ripl.start binding: binding

      if options.graph
        DynamoAutoscale.tables.each do |_, table|
          table.report! metric: :cost
          path = table.graph!
          raise 'Error saving graph.' unless path
          STDERR.puts "Graph saved to: #{path}"
          exit 3
        end
      end
    end

  end
end
