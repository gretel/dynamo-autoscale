require 'simplecov'
SimpleCov.start

# require 'timecop'

raise RuntimeError.new('you need to supply AWS_ACCESS_KEY, aborting') if ENV['AWS_ACCESS_KEY'].nil?
raise RuntimeError.new('you need to supply AWS_SECRET_KEY, aborting') if ENV['AWS_SECRET_KEY'].nil?

$logger_level = :error
TEST_CONFIG = 'dynamo-autoscale-test.yml'

require_relative 'common'
DynamoAutoscale.setup_from_config(DynamoAutoscale.config_dir(TEST_CONFIG), { :dry_run => true,
                                                                             :aws => { :access_key_id => ENV['AWS_ACCESS_KEY'],
                                                                                       :secret_access_key => ENV['AWS_SECRET_KEY'] } } )
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
