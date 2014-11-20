# dynamo-autoscale-fork - Automatic Scaling for DynamoDB
[![Build Status](https://travis-ci.org/gretel/dynamo-autoscale-fork.png?branch=master)](https://travis-ci.org/gretel/dynamo-autoscale-fork)

## Forked - what is different

The original [authors](https://github.com/invisiblehand/dynamo-autoscale/) do currently neither maintain the project nor do merge pull requests. So i got on with this fork! Hope to get my work merged upstream anytime soon.

- Command line interface (CLI) (replacing an executable and various scripts)
- Streamlined workflow using a chain of commands (`check_config`, `check_ruleset`, `pull_cw_data`, `test_simulate`, `start`) using the CLI
- Revamped logging (syntactically, semantically, and using Yell yo!)
- Can be installed and used without any superuser privileges
- Supports EC2 region 'eu-central-1'
- Works on Ruby 2.1 (tested using 2.1.5 as on AMI)
- Tests migrated to RSpec 3
- Fixed some logic glitches (nothing major though)
- Improved robustness (added sanity checks, exception handling)
- Reduced gem-dependencies and disabled some dusky codedpaths
- Overall code cleanup and various tweaks applied
- Added documentation

## $$$ Warning

**IMPORTANT**: Please read carefully before continuing! This tool, if used incorrectly, has the potential to cost you huge amounts of money. Proceeding with caution is mandatory, as we cannot be held responsible for misuse that leads to excessive cost on your AWS account.

The command line tool has a --dry_run flag to test your configuration before actually changing the provisioned throughput values. It is highly recommended that you first try running dry and inspect the output to make sure this tool works as expected. Thank you!

## Rules of the game

Welcome to the delightful mini-game that is DynamoDB provisioned throughputs.
Here are the rules of the game:

  - In a single API call, you can only change your throughput by up to 100% in
  	either direction. In other words, you can decrease as much as you want but
  	you can only increase to up to double what the current throughput is.

  - You may scale up as many times per day as you like, however you may only
  	scale down 4 times per day per table. (If you scale both reads and writes
  	down in the same request, that only counts as 1 downscale used)

  - Scaling is not an instantaneous event. It can take up to 5 minutes for a
  	table's throughput to be updated.

  - Small spikes over your threshold are tolerated but the exact amount of time
  	they are tolerated for seems to vary.

This project aims to take all of this into consideration and automatically scale your throughputs to enable you to deal with spikes and save money where possible.

# Installation

There is no gem of this fork in the Rubygems index currently. Therefore, you need to download a local copy of this gem and install it manually:

    $ gem install dynamo-autoscale-0.4.3.gem

This will install the gem containing the `dynamo-autoscale` executable. Please check the Rubygems documentation on where to expect the executable to be located. On Amazon Linux it will be in `/usr/local/bin`/. You might have to adjust your PATH environment variable accordingly.

## Configuration

The configuration file require some changes, please specify your AWS account credentials (or 'nil' them for token authentication), the tables to monitor, minimum and maximum throughput values and where your ruleset is located.

**A sample configuration can be found in 'config/dynamo-autoscale.yml'.** Please check this file for configuration details and have a copy for your changes.

This library requires AWS access right for CloudWatch and DynamoDB to retrieve data and submit changes. Using IAM, create a new user and assign the 'CloudWatch Read Only Access' policy template. In addition, you will need to use the Policy Generator to add at least the following DynamoDB actions:

  - "dynamodb:DescribeTable"
  - "dynamodb:ListTables"
  - "dynamodb:UpdateTable"
  - "cloudwatch:PutMetricAlarm"

The ARN for the custom policy can be specified as '\*' to allow access to all tables. This is required for the 'lament_wastage' command. Please refer to the IAM documentation on how to set fine-grained access limits.

### Minimal "getting started" configuration

``` yaml
:aws:
  # REQUIRED
  #
  # Here is where you specify your AWS ID and key. It needs to be a pair that
  # can access both CloudWatch and DynamoDB. For exact details on IAM policies,
  # check the project README.
  # Will try token authentication if unset.
  :access_key_id: "ABRAKADABRAOPENTHEDOOR"
  :secret_access_key: "WELLYOUSEEMTOBEANEVILINTRUDERGETTHEFU*KOFF"

  # REQUIRED
  #
  # The region that your tables are in. If you have tables in multiple regions,
  # you'll need to run multiple instances of dynamo-autoscale to handle them.
  :region: "eu-central-1"

# REQUIRED
#
# Filename (in 'rulesets/') of the ruleset. Further information on the syntax and
# purpose of rulesets can be found in the README.
:ruleset: "gradual_tail.rb"

# REQUIRED
#
# The following is an array of tables to monitor and autoscale. You need to
# specify at least one.
:tables:
  - "casino_app"
  - "cash_flow"
  - "market_shares"

# Because you are very limited by how many downscales you have per day, and
# because downscaling both reads and writes at the same time only counts as a
# single downscale, the following option will queue up downscales until it can
# apply 1 for reads and 1 for writes at the same time. It is recommended that
# you turn this one.
:group_downscales: true

# This option only works in conjunction with the above group_downscales option.
# If a downscale stays queued for a long time, you can specify a timeout and
# just apply a single read or write downscale after a specified amount of time
# passes.
#
# Specified in seconds.
:flush_after: 3600

# The following two options are configurable minimums and maximums for
# provisioned throughputs. Dynamo-autoscale will not go below or above whatever
# you set here.
:minimum_throughput: 10
:maximum_throughput: 20000

# Update the thresholds of the read/write capacity alarms of CloudWatch for
# the tables in DynamoDB. Requires permission 'cloudwatch:PutMetricAlarm'.
:update_alarms: true
```

## Rulesets

A rule set is the primary user input for dynamo-autoscale. It is a DSL for specifying when to increase and decrease your provisioned throughputs. Here is a very basic rule set:

``` ruby
reads  last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }
writes last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }

reads  for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
writes for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
```

You would put this ruleset in a file and then add the path to the ruleset to your `dynamo-autoscale` config. If you specify a relative path, the program will assume a path relative to its `Dir.pwd`.

The first two rules are designed to deal with spikes. They are saying that if the consumed capacity units is greater than 90% of the provisioned throughput for a single data point, scale the provisioned throughput up by the last consumed units multiplied by two.

For example, if we had a provisioned reads of 100 and a consumed units of
95 comes through, that will trigger that rule and the table will be scaled up to have a provisioned reads of 190.

The last two rules are controlling downscaling. Because downscaling can only happen 4 times per day per table, the rules are far less aggressive. Those rules are saying: if the consumed capacity is less than 50% of the provisioned for a whole two hours, with a minimum of 2 data points, scale the provisioned throughput to the consumed units multiplied by 2.

### The :last and :for options

These options declare how many points or what time range you want to examine. They're aliases of each other and if you specify both, one will be ignored. If you don't specify a `:min` or `:max` option, they will just get as many points as they can and evaluate the rest of the rule even if they don't get a full 2 hours of data, or a full 6 points of data. This only affects the start of the process's lifetime, eventually it will have enough data to always get the full range of points you're asking for.

### The :min and :max options

If you're not keen on asking for 2 hours of data and not receiving the full
range before evaluating the rest of the rule, you can specify a minimum or
maximum number of points to evaluate. Currently, this only supports a numeric
value. So you can ask for at least 20 points to be present like so:

``` ruby
reads for: 2.hours, less_than: "50%", min: 20, scale: { on: :consumed, by: 2 }
```

### The :greater_than and :less_than options

You must specify at least one of these options for the rule to actually validate without throwing an error. Having neither makes no sense.

You can specify either an absolute value or a percentage specified as a string. The percentage will calculate the percentage consumed against the amount provisioned.

Examples:

``` ruby
reads for: 2.hours, less_than: 10, scale: { on: :consumed, by: 2 }

reads for: 2, less_than: "20%", scale: { on: :consumed, by: 2 }
```

### The :scale option

The `:scale` option is a way of doing a simple change to the provisioned throughput without having to specify repetitive stuff in a block. `:scale` expects to be a hash and it expects to have two keys in the hash: `:on` and `:by`.

`:on` specifies what part of the metric you want to scale on. It can either by `:provisioned` or `:consumed`. In most cases, `:consumed` makes a lot more sense than `:provisioned`.

`:by` specifies the scale factor. If you want to double the provisioned capacity when a rule triggers, you would write something like this:

``` ruby
reads for: 2.hours, less_than: "30%", scale: { on: :provisioned, by: 0.5 }
```

And that would half the provisioned throughput for reads if the consumed is
less than 30% of the provisioned for 2 hours.

### Passing a block
If you want to do something a little bit more complicated with your rules, you can pass a block to them. The block will get passed three things: the table the rule was triggered for, the rule object that triggered and the actioner for that table.

An actioner is an abstraction of communication with Dynamo and it allows communication to be faked if you want to do a dry run. It exposes a very simple interface. Here's an example:

``` ruby
writes for: 2.hours, greater_than: 200 do |table, rule, actioner|
  actioner.set(:writes, 300)
end
```

This rule will set the provisioned write throughput to 300 if the consumed writes are greater than 200 for 2 hours. The actioner handles a tonne of things under the hood, such as making sure you don't scale up more than you're allowed to in a single call and making sure you don't try to change a table when it's in the updating state.

It also handles the grouping of downscales, which we will talk about in a later
section of the README.

The `table` argument is a `TableTracker` object. For a run down of what information is available to you I advise checking out the source code in `lib/dynamo-autoscale/table_tracker.rb`.

### The :times option

The `:times` option allows you to specify that a rule must be triggered a set
number of times in a row before its action is executed.

Example:

``` ruby
writes for: 10.minutes, greater_than: "90%", times: 3, scale: { on: :consumed, by: 1.5 }
```

This says that is writes are greater than 90% for 10 minutes three checks in a row, scale by the amount consumed multiplied by 1.5. A new check will only happen when the table receives new data from cloud watch, which means that the 10 minute windows could potentially overlap.

### Table-specific rules

If you only want some rules to apply to certain tables, you can do the
following:

``` ruby
table "my_table_name" do
  reads for: 2.hours, less_than: 10, scale: { on: :consumed, by: 2 }
end

reads for: 2, less_than: "20%", scale: { on: :consumed, by: 2 }
```

Anything outside of a `table` block will apply to all tables you specify in your config.

## Downscale grouping

You can downscale reads or writes individually and this will cost you one of your four downscales for the current day. Or, you can downscale reads and writes at the same time and this also costs you one of your four. (Reference: http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Limits.html)

Because of this, the actioner can handle the grouping up of downscales by adding the following to your config:

``` yaml
:group_downscales: true
:flush_after: 300
```

What this is saying is that if a write downscale came in, the actioner wouldn't fire it off immediately. It would wait 300 seconds, or 5 minutes, to see if a corresponding read downscale was triggered and would run them both at the same time. If no corresponding read came in, after 5 minutes the pending write downscale would get "flushed" and applied without a read downscale.

This technique helps to save downscales on tables that may have unpredictable consumption. You may need to tweak the `flush_after` value to match your own situation. By default, there is no `flush_after` and downscales will wait indefinitely, but this may not be desirable.

## Cloudwatch Alarms

The alarm thresholds will be updated automatically. To disable this behaviour (or if you don't want to grant `cloudwatch:PutMetricAlarm`) change the configuration file accordingly:

    :update_alarms: false

# Using the CLI - Running the tool

A command line interface is provided to manage `dynamo-autoscale` in a nice way. Requiring the gem to be installed as described above you can use your terminal shell of choice to call the command like:

    $ dynamo-autoscale ---help

The output will be

```
  NAME:

    dynamo-autoscale

  DESCRIPTION:

    CLI to manage dynamo-autoscale in a nice way.

  COMMANDS:

    check_config         Check the YAML structure of the configuration file.
    check_email          Try to send a notification email as configured.
    check_ruleset        Check the scaling ruleset defined.
    help                 Display global or [command] help documentation
    lament_wastage       Calculate what a waste of money this is (not).
    pull_cw_data         Save historic data from the CloudWatch API in JSON.
    start                Start the tool and enter the polling loop.
    test_random          Run with random data to see what would happen.
    test_simulate        Run a simulation test to check the configuration. Requires historic data available, please use the 'pull_cw_data' command.

  GLOBAL OPTIONS:

    --log_level LEVEL
        Set logging level (debug, info, warn, error, fatal).

    -h, --help
        Display help documentation

    -v, --version
        Display version information

    -t, --trace
        Display backtrace when an error occurs
```

First of all, please set up a suitable configuration for your needs. You can check the YAML structure of the configuration file using the `check_config ` command:

```
$ dynamo-autoscale check_config --config config/dynamo-autoscale.my_project.yml
    2014-11-19 18:32:36.093 [ INFO] 50703 devbox : [common] Version 0.4.2.2 (working in '/Users/tom/Sync/prjcts/dynamo-autoscale/data') starting up...
    2014-11-19 18:32:36.093 [ INFO] 50703 devbox : [main] Configuration file 'config/dynamo-autoscale.yml' seems to be OK.
    Dumping parsed configuration in YAML:
    ---
    :aws:
      :access_key_id: ABRAKADABRAOPENTHEDOOR
      :secret_access_key: WELLYOUSEEMTOBEANEVILINTRUDERGETTHEFU
      :region: eu-central-1
    :ruleset: gradual_tail.rb
    :tables:
    - casino_app
    - cash_flow
    - market_shares
    :group_downscales: true
    :flush_after: 3600
    :minimum throughput: 10
    :maximum_throughput: 20000
    :dry_run:
```

In addition, the scaling ruleset defined can be checked using the `check_ruleset` command:

```
$ dynamo-autoscale check_ruleset --config config/dynamo-autoscale.my_project.yml
  2014-11-19 18:34:45.083 [ INFO] 50854 devbox : [common] Version 0.4.2.2 (working in '/tmp/data') starting up...
  2014-11-19 18:34:45.084 [ INFO] 50854 devbox : [main] Ruleset 'gradual_tail.rb' seems to be OK.
```

To pull 'historic' data from the CloudWatch API (currently the timerange is a hardcoded week) the `pull_cw_data` command is used:

```
$ dynamo-autoscale pull_cw_data --config config/dynamo-autoscale.my_project.yml
  2014-11-19 18:36:04.470 [ INFO] 51072 devbox : [common] Version 0.4.2.2 (working in '/Users/tom/Sync/prjcts/dynamo-autoscale/data') starting up...
  2014-11-19 18:36:04.613 [ WARN] 51072 devbox : [common] Going to run dry! No throughputs will be changed for real.
  2014-11-19 18:36:05.070 [ INFO] 51072 devbox : [main] Found table 'casino_app', proceeding
  2014-11-19 18:36:05.152 [ INFO] 51072 devbox : [common] Actioner options: {:group_downscales=>true, :flush_after=>3600}
  2014-11-19 18:36:05.152 [ INFO] 51072 devbox : [common] Actioner limits: minimum throughput: 10, maximum throughput: 20000
  2014-11-19 18:36:05.154 [ INFO] 51072 devbox : [common] Loaded 8 rules from 'gradual_tail.rb'.
  2014-11-19 18:36:05.157 [ INFO] 51072 devbox : [main] Going to pull data from CloudWatch for: [Wed, 12 Nov 2014, Thu, 13 Nov 2014, Fri, 14 Nov 2014, Sat, 15 Nov 2014, Sun, 16 Nov 2014, Mon, 17 Nov 2014, Tue, 18 Nov 2014, Wed, 19 Nov 2014]
  2014-11-19 18:36:05.157 [ INFO] 51072 devbox : [main] Collecting data for 'casino_app' on '2014-11-12'..
  ....
```

Having that done you should be able to run a simulation based upon the data pulled. Check the output closeley and try to understand what is happening and if it meets your expectations:

```
$ dynamo-autoscale test_simulate --config config/dynamo-autoscale.my_project.yml
```

Each command has an additional help, let's see what `start` allows us to do:

```
$ dynamo-autoscale start --help

  NAME:

    start

  SYNOPSIS:

    dynamo-autoscale start

  DESCRIPTION:

    Start the tool and enter the polling loop.

  OPTIONS:

    -c, --config PATH
        Configuration file.

    -n, --dry_run
        Do not actually change the throughput values.
```

Now, let's use the `--dry_run` flag as explained above. It will allow us to test quite close to the real thing without messing up. So keep your umbrellas up until you feel safe to take the storm!

```
$ dynamo-autoscale start --dry_run --config config/dynamo-autoscale.my_project.yml
...
2014-11-19 21:54:21.053 [ WARN] 5683 air.jitter.local : [common] Going to run dry! No throughputs will be changed for real.
...
```

Naturally, you need to remove the `--dry_run` option to make a difference for production use.

## Logging

To run `dynamo-autoscale` using a logging level different from default of `info` the `--log_level` option is used.

    $ dynamo-autoscale start --dry_run --config config/dynamo-autoscale.my_project.yml --log_level debug

Internally, the `aws-sdk` will use the same logger to log equal or greater to level `warn`. So if things fail you should get an idea why. Having tested your setup in depth using `--log_level warn` will reduce the amount of logging waste on production use, see below.

## Exception Handling

Care has been taken to avoid exceptions and catch them if possible. It is possible to raise the logging level to see more verbose messages to increase your chance of diagnosing the issue (or finding a bug!) and get back to us on GitHub. The output can be noisy, so watch out. As far as possible exceptions get logged at level `fatal`, too.

## Expert Quickstart

Experienced users may skip all of the above. Setup a configuration file i.e. `config/dynamo-autoscale.prod.yml` and run:

    $ dynamo-autoscale start --config config/dynamo-autoscale.prod.yml --log_level warn

This can be done in a screen or let the process be managed by [Eye]https://github.com/kostya/eye) or so.

## Signalling

The `dynamo-autoscale` process responds to the `QUIT`, `SIGUSR1` and `SIGUSR2` signals.

### QUIT - Bye ...

The process will quit gracefully.

### SIGUSR1: Dump JSON

If you send `SIGUSR1` the process will dump all of the data it has been collecting on the tables to `STDERR` in JSON format. This can be used to have a logging agent grab the data.

### SIGUSR2: Human readble statistics

If you send `SIGUSR2` the process will output human readable statistics to `STDERR`:

```
Caught signal USR2! Statistics:
      Upscales : 0
    Downscales : 0
  Lost r/units : 0.0 (0.0%)
  Lost w/units : 0.0 (0.0%)
   Lost r/cost : $0.0 (0.0%)
   Lost w/cost : $0.0 (0.0%)
 Total r/units : 173.0
 Total w/units : 146.0
  Total r/cost : $0.03
  Total w/cost : $0.02
Wasted r/units : 173.0 (100.0%)
Wasted w/units : 146.0 (100.0%)
 Wasted r/cost : $0.03 (100.0%)
 Wasted w/cost : $0.02 (100.0%)
```

## Report Emails

Disabled by default, but ff you would like to receive email notifications whenever a scale event happens, you can specify some email options in your configuration. Specifying the email options implicitly activates email reports. Not including your email config implicitly turns it off.

Sample email config:

``` yaml

:email:
  :to: "devop@managing.that.mess.org"
  :from: "ec2-user@scale.like.hell.com"
  :via: :smtp
  :via_options:
    :port: 25
    :enable_starttls_auto: false
    :authentication: :plain
    :address: "mailservers.have.issu.es"
    :user_name: "authname"
    :password: "password"

:email_template: "scale_report_email.erb"
```

[Pony](https://github.com/benprew/pony)  is used internally. This part of the configuration just gets passed to Pony. Check out the documentation for more details on the options it supports.

# Developers / Tooling

Everything below this part of the README is intended for people that want to work on the dynamo-autoscale codebase or use the internal tools that we use for testing new rulesets.

## Technical details

The code has a set number of moving parts that are globally available and must
implement certain interfaces (for exact details, you would need to study the
code):

  - `DynamoAutoscale.poller`: This component is responsible for pulling data from a data source (CloudWatch or Local at the moment) and piping it into the next stage in the pipeline.

  - `DynamoAutoscale.dispatcher`: The dispatcher takes data from the poller and populates a hash table of `TableTracker` objects, as well as checking to see if any of the tables have triggered any rules.

  - `DynamoAutoscale.rules`: The ruleset contains an array of `Rule` objects inside a hash table keyed by table name. The ruleset initializer takes a file path as an argument, or a block, either of these needs to contain a set of rules (examples can be found in the `rulesets/` directory).

  - `DynamoAutoscale.actioners`: The actioners are what perform provision scaling. Locally this is faked, in production it makes API calls to DynamoDB.

  - `DynamoAutoscale.tables`: This is a hash table of `TableTracker` objects, keyed on the table name.

All of these components are globally available because most of them need access to each other and it was a pain to pass instances of them around to everybody that needed them.

They're also completely swappable. As long as they implement the right methods you can get your data from anywhere, dispatch your data to anywhere and send your actions to whatever you want. The defaults all work on local data gathered with the `script/historic_data` executable.

#### Graphing

In contrast to the upstream version this fork has graphing disabled for now due to concerns in terms of robustness. You can create graphs using the JSON data. Please see info on `SIGUSR1` above.

## Contributing

Report Issues/Feature requests on
[GitHub Issues](https://github.com/gretel/dynamo-autoscale-fork/issues).

#### Note on Patches/Pull Requests

 * Fork the project.
 * Make your feature addition or bug fix.
 * Add tests for it. This is important so we don't break it in a future version unintentionally.
 * Commit, do not modify the rakefile, version, or history.  (if you want to have your own version, that is fine but bump version in a commit by itself so it can be ignored when we pull)
 * Send a pull request. Bonus points for topic branches.

### Copyright

Copyright (c) 2013 InvisibleHand Software Ltd.
Copyright (c) 2014 Tom Hensel IT Services
See [LICENSE](https://github.com/gretel/dynamo-autoscale-fork/blob/master/LICENSE) for details.
