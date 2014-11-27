require 'spec_helper'

describe 'configuration' do
  it "should crash with no AWS region specified" do
    expect do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, aws: {})
    end.to raise_error RuntimeError
  end

  # it "should warn when using a non standard AWS region" do
  #   log = catch_logs do
  #     DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, {
  #       aws: { region: "wut" }
  #     })
  #   end
  #   bool = log[:warn].any? { |m| m.include?("wut") and m.include?("region") }
  #   expect(bool).to be_truthy
  # end

  # it "should set log level to debug when ENV['DEBUG'] is set" do
  #   with_env("DEBUG" => "true") do
  #     DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
  #     expect(DynamoAutoscale.logger.level).to eq(::Logger::DEBUG)
  #   end
  # end

  # it "should set ENV['DEBUG'] log level even when no logger config is present" do
  #   with_env("DEBUG" => "true") do
  #     DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, logger: nil)
  #     expect(DynamoAutoscale.logger.level).to eq(::Logger::DEBUG)
  #   end
  # end

  # it "should set log level to fatal when ENV['SILENT'] is set" do
  #   with_env("SILENT" => "true") do
  #     DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
  #     expect(DynamoAutoscale.logger.level).to eq(::Logger::FATAL)
  #   end
  # end

  # it "should set log level to info by default" do
  #   with_env({}) do
  #     DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
  #     expect(DynamoAutoscale.logger.level).to eq(::Logger::INFO)
  #   end
  # end

end
