# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Adjustment, type: :model do
  let!(:store) { create :store }
  let(:order) { create :order }
  let(:line_item) { create :line_item, order: order }

  let(:adjustment) { Spree::Adjustment.create!(label: 'Adjustment', adjustable: order, order: order, amount: 5) }

  context '#save' do
    let(:adjustment) { Spree::Adjustment.create(label: "Adjustment", amount: 5, order: order, adjustable: line_item) }

    it 'touches the adjustable' do
      line_item.update_columns(updated_at: 1.day.ago)
      expect { adjustment.save! }.to change { line_item.updated_at }
    end
  end

  describe 'non_tax scope' do
    subject do
      Spree::Adjustment.non_tax.to_a
    end

    let!(:tax_adjustment) do
      create(:adjustment, adjustable: order, order: order, source: create(:tax_rate))
    end

    let!(:non_tax_adjustment_with_source) do
      create(:adjustment, adjustable: order, order: order, source_type: 'Spree::Order', source_id: nil)
    end

    let!(:non_tax_adjustment_without_source) do
      create(:adjustment, adjustable: order, order: order, source: nil)
    end

    it 'select non-tax adjustments' do
      expect(subject).to_not include tax_adjustment
      expect(subject).to     include non_tax_adjustment_with_source
      expect(subject).to     include non_tax_adjustment_without_source
    end
  end

  context '#currency' do
    let(:order) { create :order, currency: 'JPY' }

    it 'returns the adjustables currency' do
      expect(adjustment.currency).to eq 'JPY'
    end

    context 'adjustable is nil' do
      before do
        adjustment.adjustable = nil
      end
      it 'uses the global currency of USD' do
        expect(adjustment.currency).to eq 'USD'
      end
    end
  end

  context "#display_amount" do
    before { adjustment.amount = 10.55 }

    it "shows the amount" do
      expect(adjustment.display_amount.to_s).to eq "$10.55"
    end

    context "with currency set to JPY" do
      let(:order) { create :order, currency: 'JPY' }

      context "when adjustable is set to an order" do
        it "displays in JPY" do
          expect(adjustment.display_amount.to_s).to eq "¥11"
        end
      end
    end
  end

  context '#recalculate' do
    subject { adjustment.recalculate }
    let(:adjustment) do
      line_item.adjustments.create!(
        label: 'Adjustment',
        order: order,
        adjustable: order,
        amount: 5,
        finalized: finalized,
        source: source,
      )
    end
    let(:order) { create(:order_with_line_items, line_items_price: 100) }
    let(:line_item) { order.line_items.to_a.first }

    context "when adjustment is finalized" do
      let(:finalized) { true }

      context 'with a promotion adjustment' do
        let(:source) { promotion.actions.first! }
        let(:promotion) { create(:promotion, :with_line_item_adjustment, adjustment_rate: 7) }

        it 'does not update the adjustment' do
          expect { subject }.not_to change { adjustment.amount }
        end
      end

      context 'with a tax adjustment' do
        let(:source) { mock_model(Spree::TaxRate, compute_amount: 10) }

        it 'updates the adjustment' do
          expect { subject }.to change { adjustment.amount }.from(5).to(10)
        end
      end

      context 'with a sourceless adjustment' do
        let(:source) { nil }

        it 'does nothing' do
          expect { subject }.not_to change { adjustment.amount }
        end
      end
    end

    context "when adjustment isn't finalized" do
      let(:finalized) { false }

      context 'with a promotion adjustment' do
        let(:source) { promotion.actions.first! }
        let(:promotion) { create(:promotion, :with_line_item_adjustment, adjustment_rate: 7) }

        around do |example|
          Spree.deprecator.silence do
            example.run
          end
        end

        context 'when the promotion is eligible' do
          it 'updates the adjustment' do
            expect { subject }.to change { adjustment.amount }.from(5).to(-7)
          end

          it 'sets the adjustment elgiible to true' do
            subject
            expect(adjustment.eligible).to eq(true)
          end
        end

        context 'when the promotion is not eligible' do
          before do
            promotion.update!(starts_at: 1.day.from_now)
          end

          it 'zeros out the adjustment' do
            expect { subject }.to change { adjustment.amount }.from(5).to(0)
          end

          it 'sets the adjustment elgiible to false' do
            subject
            expect(adjustment.eligible).to eq(false)
          end
        end
      end

      context 'with a tax adjustment' do
        let(:source) { mock_model(Spree::TaxRate, compute_amount: 10) }

        it 'updates the adjustment' do
          expect { subject }.to change { adjustment.amount }.from(5).to(10)
        end
      end

      context 'with a sourceless adjustment' do
        let(:source) { nil }

        it 'does nothing' do
          expect { subject }.to_not change { adjustment.amount }
        end
      end
    end
  end

  describe "promotion code presence error" do
    subject do
      adjustment.valid?
      adjustment.errors[:promotion_code]
    end

    context "when the adjustment is not a promotion adjustment" do
      let(:adjustment) { build(:adjustment) }

      it { is_expected.to be_blank }
    end

    context "when the adjustment is a promotion adjustment" do
      let(:adjustment) { build(:adjustment, source: promotion.actions.first) }
      let(:promotion) { create(:promotion, :with_order_adjustment) }

      context "when the promotion does not have a code" do
        it { is_expected.to be_blank }
      end

      context "when the promotion has a code" do
        let!(:promotion_code) { create(:promotion_code, promotion: promotion) }

        it { is_expected.to include("can't be blank") }
      end
    end

    context "when the adjustment is a promotion that apply automatically adjustment" do
      let(:adjustment) { build(:adjustment, source: promotion.actions.first) }
      let(:promotion) { create(:promotion, :with_order_adjustment, apply_automatically: true) }

      context "when the promotion does not have a code" do
        it { is_expected.to be_blank }
      end

      context "when the promotion has a code" do
        let!(:promotion_code) do
          promotion.codes << build(:promotion_code, promotion: promotion)
        end

        it { is_expected.to be_blank }
      end
    end
  end
end
