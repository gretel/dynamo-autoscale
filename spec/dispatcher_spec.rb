require 'spec_helper'

describe DynamoAutoscale::Dispatcher do
  let(:table_name)   { "example_table" }
  let(:table)        { DynamoAutoscale.tables[table_name] }
  let(:poller_class) { DynamoAutoscale::FakePoller }
  let(:poller_opts)  { { data: poller_data, tables: [table_name] } }

  before do
    DynamoAutoscale.poller_class = poller_class
    DynamoAutoscale.poller_opts  = poller_opts
  end

  describe "simple dispatching" do
    let(:time1) { Time.now }
    let(:time2) { time1 + 15.minutes }

    let :poller_data do
      {
        consumed_reads: {
          time1 => 10,
          time2 => 20,
        }
      }
    end

    it "should correctly dispatch data" do
      DynamoAutoscale.poller.run

      expect(table.data[time1][:consumed_reads]).to eq(10)
      expect(table.data[time2][:consumed_reads]).to eq(20)
    end
  end

  describe "dispatching out of order data" do
    let(:time1) { Time.now }
    let(:time2) { time1 + 15.minutes }

    let :poller_data do
      {
        consumed_reads: {
          time2 => 20,
          time1 => 10,
        }
      }
    end

    it "should correctly dispatch data" do
      DynamoAutoscale.poller.run

      expect(table.data[time1][:consumed_reads]).to eq(10)
      expect(table.data[time2][:consumed_reads]).to eq(20)
      expect(table.data.keys).to eq([time1, time2])
    end
  end
end
