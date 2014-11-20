require 'timecop'
require 'simplecov'
SimpleCov.start

$logger_level = :error
TEST_CONFIG = 'dynamo-autoscale-test.yml'

require_relative 'common'
DynamoAutoscale.setup_from_config(DynamoAutoscale.config_dir(TEST_CONFIG), { :dry_run => true })
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
