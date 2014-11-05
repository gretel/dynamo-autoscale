#
# Rulesets
#
# The first two rules are designed to deal with spikes. They are saying that if
# the consumed capacity units is greater than 90% of the provisioned throughput
# for a single data point, scale the provisioned throughput up by the last
# consumed units multiplied by two.
#
# For example, if we had a provisioned reads of 100 and a consumed units of 95
# comes through, that will trigger that rule and the table will be scaled up to
# have a provisioned reads of 190.
#
# The last two rules are controlling downscaling. Because downscaling can only
# happen 4 times per day per table, the rules are far less aggressive. Those
# rules are saying: if the consumed capacity is less than 50% of the provisioned
# for a whole two hours, with a minimum of 2 data points, scale the provisioned
# throughput to the consumed units multiplied by 2.
#
#
reads  last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }
writes last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }

reads  for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
writes for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }

#
# The :last and :for options
#
# These options declare how many points or what time range you want to examine.
# They're aliases of each other and if you specify both, one will be ignored. If
# you don't specify a :min or :max option, they will just get as many points as
# they can and evaluate the rest of the rule even if they don't get a full 2
# hours of data, or a full 6 points of data. This only affects the start of the
# process's lifetime, eventually it will have enough data to always get the full
# range of points you're asking for. The :min and :max options
#
# If you're not keen on asking for 2 hours of data and not receiving the full
# range before evaluating the rest of the rule, you can specify a minimum or
# maximum number of points to evaluate. Currently, this only supports a numeric
# value. So you can ask for at least 20 points to be present like so:
#
#     reads for: 2.hours, less_than: "50%", min: 20, scale: { on: :consumed, by: 2 }
#
#
# The :greater_than and :less_than options
#
# You must specify at least one of these options for the rule to actually
# validate without throwing an error. Having neither makes no sense.
#
# You can specify either an absolute value or a percentage specified as a
# string. The percentage will calculate the percentage consumed against the
# amount provisioned.
#
# Examples:
#
# reads for: 2.hours, less_than: 10, scale: { on: :consumed, by: 2 }
# reads for: 2, less_than: "20%", scale: { on: :consumed, by: 2 }
#
#
# The :scale option
#
# The :scale option is a way of doing a simple change to the provisioned
# throughput without having to specify repetitive stuff in a block. :scale
# expects to be a hash and it expects to have two keys in the hash: :on and :by.
#
# :on specifies what part of the metric you want to scale on. It can either by
# :provisioned or consumed. In most cases, consumed makes a lot more sense than
# :provisioned.
#
# :by specifies the scale factor. If you want to double the provisioned capacity
# :when a rule triggers, you would write something like this
#
#     reads for: 2.hours, less_than: "30%", scale: { on: :provisioned, by: 0.5 }
#
# And that would half the provisioned throughput for reads if the consumed is
# less than 30% of the provisioned for 2 hours.
#
#
# The :times option
#
# The :times option allows you to specify that a rule must be triggered a set
# number of times in a row before its action is executed.
#
# Example:
#
#     writes for: 10.minutes, greater_than: "90%", times: 3, scale: { on: :consumed,
#       by: 1.5 }
#
# This says that is writes are greater than 90% for 10 minutes three checks in a
# row, scale by the amount consumed multiplied by 1.5. A new check will only
# happen when the table receives new data from cloud watch, which means that the
# 10 minute windows could potentially overlap.
#
