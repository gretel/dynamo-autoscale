require 'logger'
require 'optparse'
require 'fileutils'
require 'time'
require 'csv'
require 'tempfile'
require 'aws-sdk'
require 'active_support/all'
require 'rbtree'
require 'colored'
require 'pp'
require 'erb'
require 'pony'

require_relative '../../lib/dynamo-autoscale/logger'
require_relative '../../lib/dynamo-autoscale/poller'
require_relative '../../lib/dynamo-autoscale/actioner'

module DynamoAutoscale
  include DynamoAutoscale::Logger

  module Error
    InvalidConfigurationError = Class.new(StandardError)
  end

  def self.root
    @@root ||= File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
  end

  def self.root_dir *args
    File.join(self.root, *args)
  end

  def self.data_dir *args
    root_dir 'data', *args
  end

  def self.config_dir *args
    root_dir 'config', *args
  end

  def self.rlib_dir *args
    root_dir 'rlib', *args
  end

  def self.template_dir *args
    root_dir 'templates', *args
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

  def self.load_in_order *files
    expand_paths(*files).each { |path| load path }
  end

  def self.setup_from_config path, overrides = {}
    logger.debug "[setup] Loading config..."
    self.config = YAML.load_file(path).merge(overrides)

    if config[:tables].nil? or config[:tables].empty?
      raise Error::InvalidConfigurationError.new("You need to specify at " +
        "least one table in your config's :tables section.")
    end

    filters = if config[:dry_run]
                DynamoAutoscale::LocalActioner.faux_provisioning_filters
              else
                []
              end

    if filters.empty?
      logger.debug "[setup] Not running as a dry run. Hitting production Dynamo."
    else
      logger.debug "[setup] Running as dry run. No throughputs will be changed."
    end

    DynamoAutoscale.poller_opts = {
      tables: config[:tables],
      filters: filters,
    }

    logger.debug "[setup] Poller options are: #{DynamoAutoscale.poller_opts}"

    DynamoAutoscale.actioner_opts = {
      group_downscales: config[:group_downscales],
      flush_after: config[:flush_after],
    }

    logger.debug "[setup] Actioner options are: #{DynamoAutoscale.actioner_opts}"

    if config[:minimum_throughput]
      DynamoAutoscale::Actioner.minimum_throughput = config[:minimum_throughput]
    end

    if config[:maximum_throughput]
      DynamoAutoscale::Actioner.maximum_throughput = config[:maximum_throughput]
    end

    logger.debug "[setup] Minimum throughput set to: " +
      "#{DynamoAutoscale::Actioner.minimum_throughput}"
    logger.debug "[setup] Maximum throughput set to: " +
      "#{DynamoAutoscale::Actioner.maximum_throughput}"

    logger.debug "[setup] Ruleset loading from: #{config[:ruleset]}"
    DynamoAutoscale.ruleset_location = config[:ruleset]

    logger.debug "[setup] Loaded #{DynamoAutoscale.rules.rules.values.flatten.count} rules."

    load_in_order(
      'config/services/logger.rb',
      'config/services/*.rb'
    )
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
      elsif File.exist?(full_path)
        memo << full_path
      else
        logger.warn "[load] Could not load file #{full_path}"
        STDERR.puts Kernel.caller
        exit 1
      end

      memo
    end
  end
end

DynamoAutoscale.require_in_order(
  'lib/dynamo-autoscale/**.rb',
)
