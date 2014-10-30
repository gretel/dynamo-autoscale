valid_regions = [
  'ap-northeast-1', 'ap-southeast-1', 'ap-southeast-2',
  'us-east-1', 'us-west-1', 'us-west-2',
  'eu-central-1', 'eu-west-1',
  'sa-east-1'
]

aws_config = DynamoAutoscale.config[:aws]

raise DynamoAutoscale::Error::InvalidConfigurationError.new('You must specify a :region key in' +
  ' the :aws section of your dynamo-autoscale configuration file!') unless aws_config[:region]

DynamoAutoscale::Logger.logger.warn "Specified region '#{aws_config[:region]}'" +
  ' does not appear in the list of known regions.' +
  ' Proceed with caution!' unless valid_regions.include?(aws_config[:region])

begin
  AWS.config(aws_config)
rescue RuntimeError => e
  raise e
end
