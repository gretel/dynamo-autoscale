require 'spec_helper'
require 'timecop'

describe DynamoAutoscale::TableTracker do
  let(:table_name) { "test_table" }
  let(:table)      { DynamoAutoscale::TableTracker.new(table_name) }
  subject          { table }

  before do
    table.tick(5.seconds.ago, {
                 provisioned_reads: 600.0,
                 provisioned_writes: 800.0,
                 consumed_reads: 20.0,
                 consumed_writes: 30.0,
    })

    table.tick(5.minutes.ago, {
                 provisioned_reads: 600.0,
                 provisioned_writes: 800.0,
                 consumed_reads: 20.0,
                 consumed_writes: 30.0,
    })

    table.tick(15.seconds.ago, {
                 provisioned_reads: 600.0,
                 provisioned_writes: 800.0,
                 consumed_reads: 20.0,
                 consumed_writes: 30.0,
    })
  end

  describe 'storing data' do
    specify "should be done in order" do
      expect(table.data.keys).to eq(table.data.keys.sort)
    end
  end

  describe 'retrieving data' do
    let(:now) { Time.now }

    before do
      table.tick(now, {
                   provisioned_reads: 100.0,
                   provisioned_writes: 200.0,
                   consumed_reads: 20.0,
                   consumed_writes: 30.0,
      })
    end

    describe "#name" do
      subject { table.name }
      it      { is_expected.to eq(table_name) }
    end

    describe "#earliest_data_time" do
      subject { table.earliest_data_time }
      it      { is_expected.to eq(table.data.keys.first) }
    end

    describe "#total_read_units" do
      subject { table.total_read_units }
      it      { is_expected.to eq(1900) }
    end

    describe "#total_write_units" do
      subject { table.total_write_units }
      it      { is_expected.to eq(2600) }
    end

    describe "#lost_read_units" do
      subject { table.lost_read_units }
      it      { is_expected.to eq(0) }
    end

    describe "#lost_write_units" do
      subject { table.lost_write_units }
      it      { is_expected.to eq(0) }
    end

    describe "#wasted_read_units" do
      subject { table.wasted_read_units }
      it      { is_expected.to eq(1820) }
    end

    describe "#wasted_write_units" do
      subject { table.wasted_write_units }
      it      { is_expected.to eq(2480) }
    end

    context 'AWS region us-east' do
      before { AWS.config(region: 'us-east-1') }

      describe "#total_read_cost" do
        subject { table.total_read_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end

      describe "#total_write_cost" do
        subject { table.total_write_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end

      describe "#total_read_cost" do
        subject { table.total_read_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end

      describe "#lost_write_cost" do
        subject { table.lost_write_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end

      describe "#lost_read_cost" do
        subject { table.lost_read_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end

      describe "#wasted_read_cost" do
        subject { table.wasted_read_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end

      describe "#wasted_write_cost" do
        subject { table.wasted_write_cost }
        it      { is_expected.to be_a Float }
        it      { is_expected.to be >= 0 }
      end
    end

    describe "#lost_write_percent" do
      subject { table.lost_write_percent }
      it      { is_expected.to be_a Float }
      it      { is_expected.to be >= 0 }
      it      { is_expected.to be <= 100 }
    end

    describe "#lost_read_percent" do
      subject { table.lost_read_percent }
      it      { is_expected.to be_a Float }
      it      { is_expected.to be >= 0 }
      it      { is_expected.to be <= 100 }
    end

    describe "#wasted_read_percent" do
      subject { table.wasted_read_percent }
      it      { is_expected.to be_a Float }
      it      { is_expected.to be >= 0 }
      it      { is_expected.to be <= 100 }
    end

    describe "#wasted_write_percent" do
      subject { table.wasted_write_percent }
      it      { is_expected.to be_a Float }
      it      { is_expected.to be >= 0 }
      it      { is_expected.to be <= 100 }
    end

    describe "#last 3.seconds, :consumed_reads" do
      subject { table.last 3.seconds, :consumed_reads }
      it      { is_expected.to eq([20.0]) }
    end

    describe "#last 1, :consumed_writes" do
      subject { table.last 1, :consumed_writes }
      it      { is_expected.to eq([30.0]) }
    end

    describe "#last_provisioned_for :reads" do
      subject { table.last_provisioned_for :reads }
      it      { is_expected.to eq(100.0) }
    end

    describe "#last_provisioned_for :writes, at: now" do
      subject { table.last_provisioned_for :writes, at: now }
      it      { is_expected.to eq(200.0) }
    end

    describe "#last_provisioned_for :writes, at: 3.minutes.ago" do
      subject { table.last_provisioned_for :writes, at: 3.minutes.ago }
      it      { is_expected.to eq(800.0) }
    end

    describe "#last_provisioned_for :writes, at: 3.hours.ago" do
      subject { table.last_provisioned_for :writes, at: 3.hours.ago }
      it      { is_expected.to eq(nil) }
    end

    describe "#last_consumed_for :reads" do
      subject { table.last_consumed_for :reads }
      it      { is_expected.to eq(20.0) }
    end

    describe "#last_consumed_for :writes, at: now" do
      subject { table.last_consumed_for :writes, at: now }
      it      { is_expected.to eq(30.0) }
    end

    describe "#last_consumed_for :writes, at: 3.minutes.ago" do
      subject { table.last_consumed_for :writes, at: 3.minutes.ago }
      it      { is_expected.to eq(30.0) }
    end

    describe "#last_consumed_for :writes, at: 3.hours.ago" do
      subject { table.last_consumed_for :writes, at: 3.hours.ago }
      it      { is_expected.to eq(nil) }
    end

    describe "#all_times" do
      subject      { table.all_times }

      describe '#length' do
        subject { super().length }
        it { is_expected.to eq(4) }
      end

      specify("is ordered") { expect(subject).to eq(subject.sort) }
    end

    # describe "#to_csv!" do
    #   let(:tempfile) { Tempfile.new(table_name) }
    #   subject        { File.readlines(table.to_csv!(path: tempfile.path)) }

    #   describe '#count' do
    #     subject { super().count }
    #     it { is_expected.to eq(5) }
    #   end
    #   after          { tempfile.unlink }
    # end

    describe "#report!" do
      it "should not error" do
        table.report!
      end
    end

  end

  describe 'clearing data' do
    before { table.clear_data }

    specify "table.data should be totally empty" do
      table.data.keys.each do |key|
        expect(table.data[key]).to be_empty
      end
    end
  end

  describe 'stats' do
    before do
      table.clear_data

      table.tick(3.seconds.ago, {
                   provisioned_reads: 100.0,
                   consumed_reads:    99.0,

                   provisioned_writes: 200.0,
                   consumed_writes:    198.0,
      })

      table.tick(12.seconds.ago, {
                   provisioned_reads: 100.0,
                   consumed_reads:    99.0,

                   provisioned_writes: 200.0,
                   consumed_writes:    198.0,
      })
    end

    describe 'wasted_read_units' do
      subject { table.wasted_read_units }
      it      { is_expected.to eq(2.0) }
    end

    describe 'wasted_write_units' do
      subject { table.wasted_write_units }
      it      { is_expected.to eq(4.0) }
    end

    describe 'lost_read_units' do
      before do
        table.clear_data
        table.tick(12.seconds.ago, {
                     provisioned_reads: 100.0,
                     consumed_reads:    102.0,
        })
      end

      subject { table.lost_read_units }
      it      { is_expected.to eq(2.0) }
    end

    describe 'lost_write_units' do
      before do
        table.clear_data
        table.tick(12.seconds.ago, {
                     provisioned_writes: 100.0,
                     consumed_writes:    105.0,
        })
      end

      subject { table.lost_write_units }
      it      { is_expected.to eq(5.0) }
    end
  end

  describe 'no data' do
    before { table.clear_data }

    describe 'lost_write_units' do
      subject { table.lost_write_units }
      it      { is_expected.to eq(0.0) }
    end

    describe 'lost_read_units' do
      subject { table.lost_read_units }
      it      { is_expected.to eq(0.0) }
    end

    describe 'wasted_read_units' do
      subject { table.wasted_read_units }
      it      { is_expected.to eq(0.0) }
    end

    describe 'wasted_write_units' do
      subject { table.wasted_write_units }
      it      { is_expected.to eq(0.0) }
    end

    describe "#all_times" do
      subject      { table.all_times }

      describe '#length' do
        subject { super().length }
        it { is_expected.to eq(0) }
      end
    end

    describe "#last 3.seconds, :consumed_reads" do
      subject { table.last 3.seconds, :consumed_reads }
      it      { is_expected.to eq([]) }
    end

    describe "#last 1, :consumed_writes" do
      subject { table.last 1, :consumed_writes }
      it      { is_expected.to eq([]) }
    end

    describe "#last_provisioned_for :reads" do
      subject { table.last_provisioned_for :reads }
      it      { is_expected.to be_nil }
    end

    describe "#last_provisioned_for :writes" do
      subject { table.last_provisioned_for :writes }
      it      { is_expected.to be_nil }
    end
  end

  describe 'time window' do
    describe 'inserting data outside of time window' do
      before do
        table.clear_data
        table.tick(12.weeks.ago, {
                     provisioned_reads: 600.0,
                     provisioned_writes: 800.0,
                     consumed_reads: 20.0,
                     consumed_writes: 30.0,
        })
      end

      it 'should not work' do
        expect(table.all_times).to be_empty
      end
    end

    describe 'data time based cleanup' do
      before do
        table.clear_data
        Timecop.travel(2.weeks.ago)

        table.tick(Time.now, {
                     provisioned_reads: 600.0,
                     provisioned_writes: 800.0,
                     consumed_reads: 20.0,
                     consumed_writes: 30.0,
        })

        to_the_future = Time.now + DynamoAutoscale::TableTracker::TIME_WINDOW +
          2.minutes

        Timecop.travel(to_the_future)

        table.tick(Time.now, {
                     provisioned_reads: 600.0,
                     provisioned_writes: 800.0,
                     consumed_reads: 20.0,
                     consumed_writes: 30.0,
        })
      end

      it 'should remove data outside of the time window' do
        expect(table.all_times.length).to eq(1)
      end

      it 'should not remove data inside of the time window' do
        table.tick(2.seconds.from_now, {})
        expect(table.all_times.length).to eq(2)
      end
    end
  end
end
