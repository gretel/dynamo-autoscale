require_relative '../../lib/dynamo-autoscale/logger'
require_relative '../../lib/dynamo-autoscale/actioner'
require_relative '../../lib/dynamo-autoscale/poller'

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

  def self.setup_from_config path, overrides = {}
    begin
      self.config = YAML.load_file(path).merge(overrides)
    rescue => e
      exit 2
    end

    DynamoAutoscale.require_in_order('config/services/logger.rb')

    if self.config[:tables].nil? or config[:tables].empty?
      raise RuntimeError.new("You need to configure at " +
        "least one table in the :tables section.")
    end

    if self.config[:dry_run]
      filters = DynamoAutoscale::LocalActioner.faux_provisioning_filters
      logger.warn "[common] Running dry. No throughputs will be changed for real."
    else
      filters = []
    end

    raise RuntimeError.new("Data directory '#{Dir.pwd}' is not writable") unless File.writable?(Dir.pwd)
    begin
      FileUtils.mkdir(self.data_dir) unless Dir.exists?(self.data_dir)
    rescue => e
      raise RuntimeError.new("Unable to create directory: #{self.data_dir} (#{e.inspect})")
    end

    logger.debug "[common] Data directory: #{self.data_dir}"

    DynamoAutoscale.poller_opts = {
      tables: config[:tables],
      filters: filters
    }
    logger.debug "[common] Poller options are: #{DynamoAutoscale.poller_opts}"

    DynamoAutoscale.actioner_opts = {
      group_downscales: config[:group_downscales],
      flush_after: config[:flush_after]
    }
    logger.debug "[common] Actioner options are: #{DynamoAutoscale.actioner_opts}"

    DynamoAutoscale::Actioner.minimum_throughput = config[:minimum_throughput] if config[:minimum_throughput]
    DynamoAutoscale::Actioner.maximum_throughput = config[:maximum_throughput] if config[:maximum_throughput]

    logger.debug "[common] Minimum throughput set to: " +
      "#{DynamoAutoscale::Actioner.minimum_throughput}"
    logger.debug "[common] Maximum throughput set to: " +
      "#{DynamoAutoscale::Actioner.maximum_throughput}"

    logger.debug "[common] Loading ruleset: '#{config[:ruleset]}'"
    DynamoAutoscale.ruleset_location = config[:ruleset]

    logger.debug "[common] Loaded #{DynamoAutoscale.rules.rules.values.flatten.count} rules."

    DynamoAutoscale.require_in_order('config/services/aws.rb')
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
        logger.warn "[common] Could not load file: #{full_path}"
        STDERR.puts Kernel.caller
        exit 1
      end

      memo
    end
  end
end

DynamoAutoscale.require_in_order(
  'lib/dynamo-autoscale/**.rb',
  'config/services/signals.rb'
)
