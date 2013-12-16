if config = DynamoAutoscale.config[:aws]
  valid_regions = [
    "us-east-1", "us-west-1", "us-west-2", "eu-west-1", "ap-southeast-1",
    "ap-southeast-2", "ap-northeast-1", "sa-east-1",
  ]

  unless config[:region]
    raise DynamoAutoscale::Error::InvalidConfigurationError.new("You must " +
      "specify a :region key in the :aws section of your dynamo-autoscale " +
      "configuration file!")
  end

  unless valid_regions.include?(config[:region])
    DynamoAutoscale::Logger.logger.warn "Specified region \"#{config[:region]}\"" +
      " does not appear in the valid list of regions. Proceed with caution."
  end

  AWS.config(config)
end
