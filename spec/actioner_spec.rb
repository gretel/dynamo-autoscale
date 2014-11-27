require 'spec_helper'
require 'timecop'

describe DynamoAutoscale::Actioner do
  let(:table)    { DynamoAutoscale::TableTracker.new("table") }
  let(:actioner) { DynamoAutoscale::LocalActioner.new(table) }

  before { DynamoAutoscale.current_table = table }
  after  { DynamoAutoscale.current_table = nil }
  after  { Timecop.return }

  describe "scaling down" do
    before do
      table.tick(5.minutes.ago, {
                   provisioned_writes: 15000, consumed_writes: 50,
                   provisioned_reads:  15000, consumed_reads:  20,
      })
    end

    it "should add a scale event to its table" do
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 90)).to be_truthy
      expect(table.scale_events).not_to be_empty
    end

    it "should not be allowed more than 4 times per day" do
      expect(actioner.set(:writes, 90)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 80)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 70)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 60)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 60)).to be_falsey
    end

    it "is not per metric, it is per table" do
      expect(actioner.set(:reads,  90)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 80)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:reads,  70)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 60)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 60)).to be_falsey
    end

    it "should not be allowed to fall below the minimum throughput" do
      actioner.set(:reads, DynamoAutoscale::Actioner.minimum_throughput - 1)
      time, val = actioner.provisioned_reads.last
      expect(val).to eq(DynamoAutoscale::Actioner.minimum_throughput)
    end

    it "should not be allowed to go above the maximum throughput" do
      actioner.set(:reads, DynamoAutoscale::Actioner.maximum_throughput + 1)
      time, val = actioner.provisioned_reads.last
      expect(val).to eq(DynamoAutoscale::Actioner.maximum_throughput)
    end
  end

  describe "scale resets" do
    before do
      table.tick(5.minutes.ago, {
                   provisioned_writes: 100, consumed_writes: 50,
                   provisioned_reads:  100, consumed_reads:  20,
      })
    end

    it "once per day at midnight" do
      Timecop.travel(1.day.from_now.utc.midnight - 6.hours)

      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 90)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 80)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 70)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 60)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 50)

      expect(actioner.provisioned_writes.length).to eq(4)
      expect(actioner.downscales).to eq(4)
      expect(actioner.upscales).to eq(0)
      time, value = actioner.provisioned_for(:writes).last
      expect(value).to eq(60)

      Timecop.travel(1.day.from_now.utc.midnight)

      actioner.set(:writes, 50)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 40)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 30)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 20)
      Timecop.travel(10.minutes.from_now)
      actioner.set(:writes, 10)

      expect(actioner.provisioned_writes.length).to eq(8)
      expect(actioner.downscales).to eq(4)
      expect(actioner.upscales).to eq(0)
      time, value = actioner.provisioned_for(:writes).last
      expect(value).to eq(20)
    end

    specify "and not a second sooner" do
      expect(actioner.set(:writes, 90)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 80)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 70)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 60)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 60)).to be_falsey
      expect(actioner.downscales).to eq(4)
      expect(actioner.upscales).to eq(0)

      Timecop.travel(1.day.from_now.utc.midnight - 1.second)

      expect(actioner.set(:writes, 50)).to be_falsey
      expect(actioner.downscales).to eq(4)
      expect(actioner.upscales).to eq(0)
    end
  end

  describe "scaling up" do
    before do
      table.tick(5.minutes.ago, {
                   provisioned_writes: 100, consumed_writes: 50,
                   provisioned_reads:  100, consumed_reads:  20,
      })

      expect(actioner.set(:writes, 100000)).to be_truthy
    end

    it "should only go up to 2x your current provisioned" do
      time, val = actioner.provisioned_writes.last
      expect(val).to eq(200)
    end

    it "can happen as much as it fucking wants to" do
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 200)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 300)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 400)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 500)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 600)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 700)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 800)).to be_truthy
      Timecop.travel(10.minutes.from_now)
      expect(actioner.set(:writes, 900)).to be_truthy
      Timecop.travel(10.minutes.from_now)
    end
  end

  describe "grouping actions" do
    let(:actioner) { DynamoAutoscale::LocalActioner.new(table, group_downscales: true) }

    before do
      table.tick(5.minutes.ago, {
                   provisioned_writes: 100, consumed_writes: 50,
                   provisioned_reads:  100, consumed_reads:  20,
      })
    end

    describe "writes" do
      before do
        actioner.set(:writes, 10)
      end

      it "should not apply a write without an accompanying read" do
        expect(actioner.provisioned_for(:writes).last).to be_nil
      end
    end

    describe "reads" do
      before do
        actioner.set(:reads, 10)
      end

      it "should not apply a read without an accompanying write" do
        expect(actioner.provisioned_for(:reads).last).to be_nil
      end
    end

    describe "a write and a read" do
      before do
        actioner.set(:reads, 30)
        actioner.set(:writes, 30)
      end

      it "should be applied" do
        time, value = actioner.provisioned_for(:reads).last
        expect(value).to eq(30)

        time, value = actioner.provisioned_for(:writes).last
        expect(value).to eq(30)
      end
    end

    describe "flushing after a period of time" do
      let(:actioner) do
        DynamoAutoscale::LocalActioner.new(table, {
                                             group_downscales: true,
                                             flush_after: 5.minutes,
        })
      end

      describe "happy path" do
        before do
          actioner.set(:reads, 20)
          actioner.set(:reads, 10)

          Timecop.travel(10.minutes.from_now)
          actioner.try_flush!
        end

        it "should flush" do
          expect(actioner.provisioned_reads.length).to eq(1)
          time, value = actioner.provisioned_reads.last
          expect(value).to eq(10)
        end
      end

      describe "unhappy path" do
        before do
          actioner.set(:reads, 20)
          actioner.set(:reads, 10)
          actioner.try_flush!
        end

        it "should not flush" do
          expect(actioner.provisioned_reads.length).to eq(0)
          time, value = actioner.provisioned_reads.last
          expect(value).to be_nil
        end
      end
    end
  end
end
