module DynamoAutoscale
  module Helpers
    module EnvironmentHelper
      def with_env env, &block
        old_env = ENV.respond_to?(:to_h) ? ENV.to_h.dup : ENV.to_hash.dup
        ENV.clear
        env.each { |h, k| ENV[h] = k }
        block.call
        ENV.clear
        old_env.each { |h, k| ENV[h] = k }
        nil
      end
    end
  end
end
