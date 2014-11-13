require 'rspec/core/rake_task'
require 'bundler/gem_tasks'

require_relative './lib/dynamo-autoscale/version'

STDERR.sync = true
STDOUT.sync = true

# task :default => [:test]
desc "Run all tests"
RSpec::Core::RakeTask.new(:test)

desc "Build gem"
task :build do
  success = system('gem build dynamo-autoscale.gemspec')
  raise RuntimeError.new('gem build failed, aborting.') unless success
end
