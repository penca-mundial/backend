# frozen_string_literal: true

require "rails_helper"

RSpec.describe Matches::LockPredictions do
  let(:match) { create(:match) }

  it "locks all open predictions and returns how many it locked" do
    create_list(:prediction, 2, match: match)

    result = described_class.call(match: match)

    expect(result).to be_success
    expect(result.data).to eq(2)
    expect(Prediction.where(match: match).pluck(:locked_at)).to all(be_present)
  end

  it "leaves already-locked predictions untouched" do
    locked = create(:prediction, match: match, locked_at: 1.hour.ago)
    open   = create(:prediction, match: match)
    previous = locked.reload.locked_at

    result = described_class.call(match: match)

    expect(result.data).to eq(1)
    expect(locked.reload.locked_at).to be_within(1.second).of(previous)
    expect(open.reload.locked_at).to be_present
  end
end
