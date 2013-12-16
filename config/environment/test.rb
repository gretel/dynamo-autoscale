ENV['RACK_ENV'] = "test"

# SimpleCov seems to get confused when you load a file into your code multiple
# times. It will wipe all of its current data about that file when it gets
# reloaded, so some of our coverage stats are less than they should be.
require 'simplecov'
SimpleCov.start

require_relative 'common'
require 'timecop'

TEST_CONFIG_PATH = DynamoAutoscale.config_dir('dynamo-autoscale-test.yml')
DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)

DynamoAutoscale.require_in_order(
  'spec/helpers/**.rb'
)

RSpec.configure do |config|
  config.include DynamoAutoscale::Helpers::LoggerHelper
  config.include DynamoAutoscale::Helpers::EnvironmentHelper
end
