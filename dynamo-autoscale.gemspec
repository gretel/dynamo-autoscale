require 'date'

require './lib/dynamo-autoscale/version'

Gem::Specification.new do |gem|
  gem.name    = 'dynamo-autoscale-fork'
  gem.version = DynamoAutoscale::VERSION
  gem.date    = Date.today.to_s

  gem.summary = 'Automatic Scaling for DynamoDB.'
  gem.description = 'Will automatically monitor DynamoDB tables and scale them based on rules.'

  gem.authors  = ['gretel', 'InvisibleHand']
  gem.email    = 'github@jitter.eu'
  gem.homepage = 'http://github.com/gretel/dynamo-autoscale-fork'

  gem.bindir      = ['bin']
  gem.executables = ['dynamo-autoscale']

  gem.license  = 'MIT'

  gem.required_ruby_version = '>= 1.9.3'

  # gem.requirements << 'If you want to graph your tables, you'll need R with ' +
  #   'the ggplot and reshape packages installed.'

  gem.add_runtime_dependency 'activesupport', '~> 4.1'
  gem.add_runtime_dependency 'aws-sdk-v1', '~> 1'
  gem.add_runtime_dependency 'commander', '~> 4'
  gem.add_runtime_dependency 'oj', '~> 2'
  gem.add_runtime_dependency 'oj_mimic_json', '~> 1'
  gem.add_runtime_dependency 'pony', '~> 1'
  gem.add_runtime_dependency 'rbtree', '~> 0.4', '>= 0.4.1'
  gem.add_runtime_dependency 'timecop', '~> 0.7'
  gem.add_runtime_dependency 'yell', '~> 2'

  # ensure the gem is built out of versioned files
  gem.files = `git ls-files -z`.split("\0")
end
