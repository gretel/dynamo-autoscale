require_relative '../../lib/dynamo-autoscale/logger'
require_relative '../../lib/dynamo-autoscale/actioner'
require_relative '../../lib/dynamo-autoscale/poller'

LOGGER_FORMAT = "%d [%5L] %p %h : %m"
LOGGER_TIME_FORMAT = "%F %T.%L"

module DynamoAutoscale
  include DynamoAutoscale::Logger

  def self.root
    File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
  end

  def self.root_dir *args
    File.join(self.root, *args)
  end

  def self.data_dir *args
    # if gem is installed by !user the root dir will no be writable
    # root_dir 'data', *args
    File.expand_path(File.join(Dir.pwd, 'data'))
  end

  def self.config_dir *args
    root_dir 'config', *args
  end

  def self.rlib_dir *args
    root_dir 'rlib', *args
  end

  def self.templates_dir *args
    root_dir 'templates', *args
  end

  def self.rulesets_dir *args
    root_dir 'rulesets', *args
  end

  def self.config
    @@config ||= {}
  end

  def self.config= new_config
    @@config = new_config
  end

  def self.require_in_order *files
    expand_paths(*files).each { |path| require path }
  end

  def self.setup_logger(log_level)
    require 'yell'

    # dont buffer these, might be important
    STDERR.sync = true

    # enforce logging level defaults if unset
    $logger_level ||= DEFAULT_LOG_LEVEL

    # see https://github.com/rudionrails/yell .. https://github.com/rudionrails/yell/wiki/101-formatting-log-messages
    DynamoAutoscale::Logger.logger = Yell.new do |l|
      l.adapter :stdout, level: "gte.#{$logger_level}", format: Yell.format(LOGGER_FORMAT, LOGGER_TIME_FORMAT)
      l.adapter :stderr, level: [:error, :fatal], format: Yell.format(LOGGER_FORMAT, LOGGER_TIME_FORMAT)
    end

    logger.debug "[logger] Ready (#{logger.level.inspect})"
  end

  def self.load_config path, overrides = {}
    begin
      self.config = YAML.load_file(path).merge(overrides)
    rescue => e
      raise RuntimeError.new("Error loading configuration (#{e})")
    end
  end

  def self.setup_aws
    require 'aws-sdk-v1'

    # supress warning
    I18n.enforce_available_locales = false

    valid_regions = [
      'ap-northeast-1', 'ap-southeast-1', 'ap-southeast-2',
      'us-east-1', 'us-west-1', 'us-west-2',
      'eu-central-1', 'eu-west-1',
      'sa-east-1'
    ]

    aws_config = DynamoAutoscale.config[:aws].merge(:logger => DynamoAutoscale.logger, :log_level => :debug)

    raise DynamoAutoscale::Error::InvalidConfigurationError.new('You must specify a :region key in' +
      ' the :aws section of your dynamo-autoscale configuration file!') unless aws_config[:region]

    DynamoAutoscale::Logger.logger.warn "Specified region '#{aws_config[:region]}'" +
      ' does not appear in the list of known regions.' +
      ' Proceed with caution!' unless valid_regions.include?(aws_config[:region])

    begin
      AWS.config(aws_config)
    rescue RuntimeError => e
      raise e
    end
  end

  def self.setup
    if self.config[:tables].nil? or config[:tables].empty?
      raise RuntimeError.new("You need to configure at " +
        "least one table in the :tables section of the configuration file.")
    end

    # sanity checks on data directory
    raise RuntimeError.new("Data directory '#{Dir.pwd}' is not writable") unless File.writable?(Dir.pwd)
    begin
      FileUtils.mkdir(self.data_dir) unless Dir.exists?(self.data_dir)
    rescue => e
      raise RuntimeError.new("Unable to create directory: #{self.data_dir} (#{e.inspect})")
    end

    # connect to the thing in the sky
    DynamoAutoscale.setup_aws

    # enforce default
    $dry_run ||= true
    if $dry_run
      filters = DynamoAutoscale::LocalActioner.faux_provisioning_filters
      logger.warn '[common] Going to run dry! No throughputs will be changed for real.'
    else
      filters = []
    end

    tables = []
    config[:tables].each do |table_name|
      if AWS::DynamoDB.new.tables[table_name].exists?
        DynamoAutoscale.logger.info "[main] Found table '#{table_name}', proceeding"
        tables << table_name
      else
        DynamoAutoscale.logger.warn "[main] Unable to find table '#{table_name}', excluding"
      end
    end
    raise RuntimeError.new("[main] At least one table must exists, aborting") if tables.empty?

    DynamoAutoscale.poller_opts = {
      tables: tables,
      filters: filters
    }

    DynamoAutoscale.actioner_opts = {
      group_downscales: config[:group_downscales],
      flush_after: config[:flush_after]
    }

    DynamoAutoscale::Actioner.minimum_throughput = config[:minimum_throughput] if config[:minimum_throughput]
    DynamoAutoscale::Actioner.maximum_throughput = config[:maximum_throughput] if config[:maximum_throughput]
    logger.info "[common] Actioner limits: minimum throughput: #{DynamoAutoscale::Actioner.minimum_throughput}, maximum throughput: #{DynamoAutoscale::Actioner.maximum_throughput}"

    DynamoAutoscale.ruleset_location = config[:ruleset]
    logger.info "[common] Loaded #{DynamoAutoscale.rules.rules.values.flatten.count} rules from '#{config[:ruleset]}'."

    DynamoAutoscale.handle_signals
  end

  def self.handle_signals
    Signal.trap('USR1') do
      STDERR.puts "Caught signal USR1! Dumping data in JSON:"
      STDERR.puts tables.to_json
    end

    Signal.trap('USR2') do
      STDERR.puts 'Caught signal USR2! Graphing disabled.'
    #   DynamoAutoscale.logger.info "[common] Caught signal USR2. Dumping graphs for all tables to '#{Dir.pwd}'"

    #   DynamoAutoscale.tables.each do |name, table|
    #     # TODO: abstraction
    #     table.graph! output_file: File.join(Dir.pwd, "#{table.name}_graph.png"), r_script: 'dynamodb_graph.r'
    #     table.graph! output_file: File.join(Dir.pwd, "#{table.name}_scatter.png"), r_script: 'dynamodb_scatterplot.r'
    #   end
    end

    Kernel.trap('EXIT') do
      STDOUT.puts 'Bye, bye.'
    end

    Kernel.trap('QUIT') do
      STDERR.puts 'Caught signal QUIT, shutting down...'
      sleep 1
      exit 0
    end

  end

  def self.dispatcher= new_dispatcher
    @@dispatcher = new_dispatcher
  end

  def self.dispatcher
    @@dispatcher ||= Dispatcher.new
  end

  def self.poller_opts= new_poller_opts
    @@poller_opts = new_poller_opts
  end

  def self.poller_opts
    @@poller_opts ||= {}
  end

  def self.poller_class= new_poller_class
    @@poller_class = new_poller_class
  end

  def self.poller_class
    @@poller_class ||= LocalDataPoll
  end

  def self.poller= new_poller
    @@poller = new_poller
  end

  def self.poller
    @@poller ||= poller_class.new(poller_opts)
  end

  def self.actioner_class= klass
    @@actioner_class = klass
  end

  def self.actioner_class
    @@actioner_class ||= LocalActioner
  end

  def self.actioner_opts= new_opts
    @@actioner_opts = new_opts
  end

  def self.actioner_opts
    @@actioner_opts ||= {}
  end

  def self.actioners
    @@actioners ||= Hash.new do |h, k|
      h[k] = actioner_class.new(k, actioner_opts)
    end
  end

  def self.actioners= new_actioners
    @@actioners = new_actioners
  end

  def self.reset_tables
    @@tables = Hash.new { |h, k| h[k] = TableTracker.new(k) }
  end

  def self.tables
    @@tables ||= Hash.new { |h, k| h[k] = TableTracker.new(k) }
  end

  def self.ruleset_location
    @@ruleset_location ||= nil
  end

  def self.ruleset_location= new_ruleset_location
    @@ruleset_location = new_ruleset_location
  end

  def self.rules
    @@rules ||= RuleSet.new(ruleset_location)
  end

  def self.current_table= new_current_table
    @@current_table = new_current_table
  end

  def self.current_table
    @@current_table ||= nil
  end

  private

  # Expands strings given to it as paths relative to the project root
  def self.expand_paths *files
    files.inject([]) do |memo, path|
      full_path = root_dir(path)

      if (paths = Dir.glob(full_path)).length > 0
        memo += paths.select { |p| File.file?(p) }
      elsif File.exist?("#{full_path}.rb")
        memo << "#{full_path}.rb"
      else
        STDERR.puts "Error loading file: #{full_path} (#{Kernel.caller}"
        exit 1
      end

      memo
    end
  end
end

DynamoAutoscale.require_in_order(
  'lib/dynamo-autoscale/**.rb',
)
