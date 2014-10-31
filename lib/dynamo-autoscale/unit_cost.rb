module DynamoAutoscale
  class UnitCost
    # Pricing information obtained from: http://aws.amazon.com/dynamodb/pricing/
    HOURLY_PRICING = {
      # US East (Northern Virginia)
      'us-east-1' => {
        :rd => [ 0.0065, 50 ],
        :wr => [ 0.0065, 10 ],
      },
      # US West (Northern California)
      'us-west-1' => {
        :rd => [ 0.0065, 50 ],
        :wr => [ 0.0065, 10 ]
      },
      # US West (Oregon)
      'us-west-2' => {
        :rd => [ 0.0065, 50 ],
        :wr => [ 0.0065, 10 ]
      },
      # Asia Pacific (Singapore)
      'ap-southeast-1' => {
        :rd => [ 0.0074, 50 ],
        :wr => [ 0.0074, 10 ]
      },
      # Asia Pacific (Sydney)
      'ap-southeast-2' => {
        :rd => [ 0.0074, 50 ],
        :wr => [ 0.0074, 10 ]
      },
      # Asia Pacific (Tokyo)
      'ap-northeast-1' => {
        :rd => [ 0.0078, 50 ],
        :wr => [ 0.0078, 10 ]
      },
      # European Union (Frankfurt)
      'eu-central-1' => {
        :rd => [ 0.00793, 50 ],
        :wr => [ 0.00793, 10 ]
      },
      # European Union (Ireland)
      'eu-west-1' => {
        :rd => [ 0.00735, 50 ],
        :wr => [ 0.00735, 10 ]
      },
      # South America (Sao Paulo)
      'sa-east-1' => {
        :rd => [ 0.00975, 50 ],
        :wr => [ 0.00975, 10 ]
      }
    }

    # Returns the cost of N read units for an hour in the region given by
    # AWS.config.region
    #
    # Example:
    #
    #   DynamoAutoscale::UnitCost.read(500)
    #   #=> 0.065
    def self.read units, opts = {}
      pricing = HOURLY_PRICING[AWS.config.region]
      raise RangeError.new("Unable to determine read pricing for '#{AWS.config.region}'") unless pricing
      ((units / pricing[:rd][1].to_f) * pricing[:rd][0])
    end

    # Returns the cost of N write units for an hour in the region given by
    # AWS.config.region.
    #
    # Example:
    #
    #   DynamoAutoscale::UnitCost.write(500)
    #   #=> 0.325
    def self.write units, opts = {}
      pricing = HOURLY_PRICING[AWS.config.region]
      raise RangeError.new("Unable to determine write pricing for '#{AWS.config.region}'") unless pricing
      ((units / pricing[:rd][1].to_f) * pricing[:wr][0])
    end

  end
end
