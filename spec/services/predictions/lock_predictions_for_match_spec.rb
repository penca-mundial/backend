# frozen_string_literal: true

require "rails_helper"

RSpec.describe Predictions::LockPredictionsForMatch do
  let(:game) { create(:match) }

  it "locks all open predictions and returns how many it locked" do
    create_list(:prediction, 2, match: game)

    result = described_class.call(match: game)

    expect(result).to be_success
    expect(result.data).to eq(2)
    expect(Prediction.where(match: game).pluck(:locked_at)).to all(be_present)
  end

  it "leaves already-locked predictions untouched" do
    locked = create(:prediction, match: game, locked_at: 1.hour.ago)
    open   = create(:prediction, match: game)
    previous = locked.reload.locked_at

    result = described_class.call(match: game)

    expect(result.data).to eq(1)
    expect(locked.reload.locked_at).to be_within(1.second).of(previous)
    expect(open.reload.locked_at).to be_present
  end

  it "is idempotent: a second run locks nothing more" do
    create_list(:prediction, 2, match: game)
    described_class.call(match: game)

    expect(described_class.call(match: game).data).to eq(0)
  end
end
