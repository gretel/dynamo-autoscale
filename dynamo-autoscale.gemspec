require 'date'

require './lib/dynamo-autoscale/version'

Gem::Specification.new do |gem|
  gem.name    = 'dynamo-autoscale'
  gem.version = DynamoAutoscale::VERSION
  gem.date    = Date.today.to_s

  gem.summary = "Autoscaling for DynamoDB provisioned throughputs."
  gem.description = "Will automatically monitor DynamoDB tables and scale them based on rules."

  gem.authors  = ['InvisibleHand','gretel']
  gem.email    = 'developers@getinvisiblehand.com'
  gem.homepage = 'http://github.com/invisiblehand/dynamo-autoscale'

  gem.bindir      = ['bin']
  gem.executables = ['dynamo-autoscale']

  gem.license  = 'MIT'

  gem.required_ruby_version = '>= 1.9.3'

  gem.requirements << "If you want to graph your tables, you'll need R with " +
    "the ggplot and reshape packages installed."

  gem.add_runtime_dependency 'activesupport'
  gem.add_runtime_dependency 'aws-sdk-v1'
  gem.add_runtime_dependency 'colored'
  gem.add_runtime_dependency 'commander'
  gem.add_runtime_dependency 'eye'
  gem.add_runtime_dependency 'mono_logger' unless RUBY_VERSION.to_i < 2
  gem.add_runtime_dependency 'oj'
  gem.add_runtime_dependency 'oj_mimic_json'
  gem.add_runtime_dependency 'pony'
  gem.add_runtime_dependency 'rbtree', '~> 0.4', '>= 0.4.1'
  # gem.add_runtime_dependency 'ruby-prof'
  gem.add_runtime_dependency 'timecop'

  # ensure the gem is built out of versioned files
  gem.files = `git ls-files -z`.split("\0")
end
