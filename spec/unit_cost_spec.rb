require 'spec_helper'

describe DynamoAutoscale::UnitCost do
  context 'region: us-east-1' do
    before { AWS.config(region: 'us-east-1') }

    specify "#write should return a number" do
      subject.class.write(50).should be_a Float
    end

    specify "#read should return a number" do
      subject.class.read(50).should be_a Float
    end
  end

  context 'region: us-west-1' do
    before { AWS.config(region: 'us-west-1') }

    specify "#write should return a number" do
      subject.class.write(50).should be_a Float
    end

    specify "#read should return a number" do
      subject.class.read(50).should be_a Float
    end
  end

  context 'region: not-a-region' do
    before { AWS.config(region: 'not-a-region') }

    specify "#write should return nil" do
      subject.class.write(50).should be_nil
    end

    specify "#read should return nil" do
      subject.class.read(50).should be_nil
    end
  end
end
