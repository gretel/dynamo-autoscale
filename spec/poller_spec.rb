require 'spec_helper'

describe DynamoAutoscale::Poller do
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
      DynamoAutoscale.dispatcher.should_receive(:dispatch).with(
        table, time1, { consumed_reads: 10 }
      ).once

      DynamoAutoscale.dispatcher.should_receive(:dispatch).with(
        table, time2, { consumed_reads: 20 }
      ).once

      DynamoAutoscale.poller.run
    end
  end
end
