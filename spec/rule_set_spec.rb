require 'spec_helper'

describe DynamoAutoscale::RuleSet do
  describe 'creating rules' do
    let :rules do
      DynamoAutoscale::RuleSet.new do
        table "test" do
          reads  greater_than: 50, for: 5.minutes do

          end

          writes greater_than: 100, for: 15.minutes do

          end
        end

        table :all do
          reads less_than: 20, for: 2 do

          end
        end

        writes greater_than: "40%", for: 12.seconds do

        end
      end
    end

    describe 'for a single table' do
      subject      { rules.for "test" }

      describe '#length' do
        subject { super().length }
        it { is_expected.to eq(4) }
      end
    end

    describe 'for all tables' do
      subject      { rules.for :all }

      describe '#length' do
        subject { super().length }
        it { is_expected.to eq(2) }
      end
    end
  end

  describe 'using rules' do
    let :rules do
      DynamoAutoscale::RuleSet.new do
        table "test_table" do
          reads  greater_than: 50, for: 5.minutes do
            @__first = true
          end

          reads  greater_than: 100, for: 15.minutes do
            @__second = true
          end
        end

        reads greater_than: "40%", for: 12.minutes do
          @__third = true
        end
      end
    end

    describe 'earlier rules get precedence' do
      let(:table) { DynamoAutoscale::TableTracker.new("test_table") }

      before do
        table.tick(4.minutes.ago, {
                     provisioned_reads: 100.0,
                     provisioned_writes: 200.0,
                     consumed_reads: 90.0,
                     consumed_writes: 30.0,
        })

        rules.test(table)
      end

      describe 'first block should get called' do
        subject { rules.instance_variable_get(:@__first) }
        it      { is_expected.to be_truthy }
      end

      describe 'second block should not get called' do
        subject { rules.instance_variable_get(:@__second) }
        it      { is_expected.to be_nil }
      end

      describe 'third block should not get called' do
        subject { rules.instance_variable_get(:@__third) }
        it      { is_expected.to be_nil }
      end
    end
  end
end
