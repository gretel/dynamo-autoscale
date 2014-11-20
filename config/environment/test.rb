require 'timecop'
require 'simplecov'

SimpleCov.start

require_relative 'common'

TEST_CONFIG_PATH = DynamoAutoscale.config_dir('dynamo-autoscale-test.yml')

$log_level = :debug
DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, { :dry_run => true })

DynamoAutoscale.require_in_order(
  'spec/helpers/**.rb'
)

RSpec.configure do |config|
  # TODO: fix that thang
  config.include DynamoAutoscale::Helpers::LoggerHelper
  config.include DynamoAutoscale::Helpers::EnvironmentHelper

  config.before(:each) do
    DynamoAutoscale.reset_tables
    DynamoAutoscale.dispatcher = nil
    DynamoAutoscale.actioners  = nil
    DynamoAutoscale.poller     = nil
  end
end
