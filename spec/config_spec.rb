require 'spec_helper'

describe 'configuration' do
  it "should crash with no AWS region specified" do
    expect do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, aws: { })
    end.to raise_error DynamoAutoscale::Error::InvalidConfigurationError
  end

  it "should warn when using a non standard AWS region" do
    log = catch_logs do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, {
        logger: nil,
        aws:    { region: "wut" }
      })
    end

    bool = log[:warn].any? { |m| m.include?("wut") and m.include?("region") }
    bool.should be_true
  end

  it "should set log level to debug when ENV['DEBUG'] is set" do
    with_env("DEBUG" => "true") do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
      DynamoAutoscale.logger.level.should == ::Logger::DEBUG
    end
  end

  it "should set ENV['DEBUG'] log level even when no logger config is present" do
    with_env("DEBUG" => "true") do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, logger: nil)
      DynamoAutoscale.logger.level.should == ::Logger::DEBUG
    end
  end

  it "should set log level to fatal when ENV['SILENT'] is set" do
    with_env("SILENT" => "true") do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
      DynamoAutoscale.logger.level.should == ::Logger::FATAL
    end
  end

  it "should set log level to info by default" do
    with_env({}) do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
      DynamoAutoscale.logger.level.should == ::Logger::INFO
    end
  end

  it "DEBUG should take precedence over SILENT" do
    with_env("SILENT" => "true", "DEBUG" => "true") do
      DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH)
      DynamoAutoscale.logger.level.should == ::Logger::DEBUG
    end
  end

  it "should use a standard formatter when pretty is not specified" do
    DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, {
      logger: {}
    })

    DynamoAutoscale.logger.formatter.should be_a DynamoAutoscale::StandardFormatter
  end

  it "should use a pretty formatter when pretty is specified" do
    DynamoAutoscale.setup_from_config(TEST_CONFIG_PATH, {
      logger: { style: "pretty" }
    })

    DynamoAutoscale.logger.formatter.should be_a DynamoAutoscale::PrettyFormatter
  end
end
