module DynamoAutoscale
  class CLI

    def self.run(name, options)
      require_relative '../../config/environment/common'

      raise RuntimeError.new("Configuration file '#{options.config}' does not exist") unless File.exists?(options.config)
      DynamoAutoscale.logger.info "[common] Version #{DynamoAutoscale::VERSION} (working in '#{DynamoAutoscale.data_dir}') starting up..."

      if options.skip_setup
        DynamoAutoscale.load_config(File.realpath(options.config), { :dry_run => $dry_run })
      else
        DynamoAutoscale.setup_from_config(File.realpath(options.config), { :dry_run => $dry_run })
      end

      begin
        self.send(name, options)
      rescue => e
        DynamoAutoscale.logger.fatal "[main] Exception caught: #{e}"
        raise e
      end
    end

    private

    def self.start(options)
      DynamoAutoscale.poller_class = DynamoAutoscale::CWPoller
      DynamoAutoscale.actioner_class = DynamoAutoscale::DynamoActioner unless DynamoAutoscale.config[:dry_run]
      DynamoAutoscale.poller.backdate
      DynamoAutoscale.logger.info "[main] Starting main loop..."
      DynamoAutoscale.poller.run
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
        rule_set = DynamoAutoscale::RuleSet.new(DynamoAutoscale.config[:ruleset])
      rescue ArgumentError => e
        DynamoAutoscale.logger.fatal "[main] Ruleset '#{DynamoAutoscale.config[:ruleset]}' has errors!"
        exit 1
      end
      DynamoAutoscale.logger.info "[main] Ruleset '#{DynamoAutoscale.config[:ruleset]}' seems to be OK."
      # STDERR.puts "Dumping ruleset object as YAML:"
      # STDERR.puts rule_set.rules.to_yaml
    end

    def self.check_config(options)
      DynamoAutoscale.logger.info "[main] Configuration file '#{options.config}' seems to be OK."
      STDERR.puts "Dumping parsed configuration in YAML:"
      STDERR.puts DynamoAutoscale.config.to_yaml
    end

    def self.pull_cw_data(options)
      require 'fileutils'

      # This script will fetch historic data from all of the tables that
      # you have specified in the configuration file.
      #
      # It will store this data into the `data' in the working directory in JSON.
      #
      window = DynamoAutoscale::TableTracker::TIME_WINDOW
      interval = DynamoAutoscale::CWPoller::INTERVAL
      range  = (Date.today - window).upto(Date.today)

      DynamoAutoscale.logger.info "[main] Going to pull data from CloudWatch for: #{range.to_a}"
      # Filter out tables that do not exist in Dynamo.
      DynamoAutoscale.poller_opts[:tables].each do |table|
        range.each do |start_day|
          dir = DynamoAutoscale.data_dir(start_day.to_s)
          end_day = start_day + 1.day
          DynamoAutoscale.logger.info "[main] Collecting data for '#{table}' on '#{start_day}'..."
          metrics = Metrics.all_metrics(table, {
            period:     interval,
            start_time: start_day,
            end_time:   end_day,
          })
          File.open(File.join(dir, "#{table}.json"), 'w') do |file|
            json = JSON.pretty_generate(metrics)
            file.write(json)
            STDERR.puts json # dump data
          end
        end
      end
    end

    def self.lament_wastage(options)
      # This calculates an approximate "wastage cost" for every table (wastage
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

        DynamoAutoscale.logger.info "[main] Wastage: #{table.rjust(pad)}: reads(#{cr.round(4)} / #{pr.round(4)}) " +
             "writes(#{cw.round(4)} / #{pw.round(4)}), ~$#{waste_cost.round(4)} per hour. Total waste cost: ~$#{total_waste.round(4)} per hour."
      end
    end

    def self.test_simulate(options)
      require 'timecop'

      DynamoAutoscale.poller_class = DynamoAutoscale::LocalDataPoll
      DynamoAutoscale.poller.run do |table, time, datum|
        Timecop.travel(time)
        STDERR.puts "Event at #{time}: #{datum.pretty_inspect} - Press CTRL-C to abort."
        gets
      end
    end

    def self.test_random(options)
      # You will first need to have obtained historic data on the tables in your
      # config file. To do this, run:
      #
      #   $ dynamo-autoscale pull_cw_data --config path/to/config.yml
      #
      # This does not change any throughputs on DynamoDB. Whatsoever, the
      # CloudWatch API will be hit fairly hard to get the data.
      require 'timecop'

      # RubyProf.start
      DynamoAutoscale.poller_class = DynamoAutoscale::RandomDataGenerator
      DynamoAutoscale.poller_opts  = {
        num_points: 250,
        start_time: Time.now,
        provisioned_reads: 1000,
        provisioned_writes: 1200,
      }.merge(DynamoAutoscale.poller_opts)
      DynamoAutoscale.logger.debug "[main] Poller options: #{DynamoAutoscale.poller_opts}"
      DynamoAutoscale.poller.run { |table_name, time| Timecop.travel(time) }
      # printer = RubyProf::FlatPrinter.new(RubyProf.stop)
      # printer.print(STDOUT, min_percent: 2)

      # if options.graph
      #   DynamoAutoscale.tables.each do |_, table|
      #     table.report!
      #     path = table.graph!
      #     raise 'Error saving graph.' unless path
      #     STDERR.puts "Graph saved to: #{path}"
      #     exit 3
      #   end
      # end
    end

  end
end
