require 'rspec/core/rake_task'
require 'bundler/gem_tasks'

STDERR.sync = true
STDOUT.sync = true

task :default => [:test, :build]

desc 'Run all tests'
RSpec::Core::RakeTask.new(:test)

desc 'Build Gem'
task :build do
  `git pull`
  success = system('gem build dynamo-autoscale.gemspec')
  raise RuntimeError.new('gem build failed, aborting.') unless success
end
