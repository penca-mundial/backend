# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchLockJob do
  it "uses the :default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  describe "#perform" do
    let(:match) { create(:match) }
    let!(:predictions) { create_list(:prediction, 2, match: match) }

    it "locks every open prediction for the match" do
      expect { described_class.perform_now(match.id) }
        .to change { predictions.count { |p| p.reload.locked_at.present? } }.from(0).to(2)
    end

    it "is idempotent: a second run does not move the lock time" do
      described_class.perform_now(match.id)
      locked_at = predictions.first.reload.locked_at

      described_class.perform_now(match.id)

      expect(predictions.first.reload.locked_at).to eq(locked_at)
    end

    it "delegates to Matches::LockPredictions" do
      expect(Matches::LockPredictions).to receive(:call).with(match: match).and_call_original

      described_class.perform_now(match.id)
    end
  end
end
