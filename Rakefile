require 'rspec/core/rake_task'
require 'bundler/gem_tasks'

task :default => [:test]

desc "Run all tests"
RSpec::Core::RakeTask.new(:test) do |t|
  t.rspec_opts = '-cfs'
end

require 'rake/packagetask'
require './lib/dynamo-autoscale/version'

Rake::PackageTask.new('dynamo_autoscale', DynamoAutoscale::VERSION) do |p|
  p.need_tar = true
  p.package_files.include('lib/**/*.rb')
  # TODO: appbundler
  p.package_files.include('bin/dynamo-autoscale')
  p.package_files.include('config/**/*.rb')
  p.package_files.include('config/*.yml')
  p.package_files.include('rlib/*.r')
  p.package_files.include('rulesets/*.rb')
  p.package_files.include('templates/*.erb')
end
