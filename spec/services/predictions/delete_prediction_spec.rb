# frozen_string_literal: true

require "rails_helper"

RSpec.describe Predictions::DeletePrediction do
  it "deletes the prediction when its match is still open" do
    prediction = create(:prediction, match: create(:match, kickoff_at: 1.week.from_now))

    result = described_class.call(prediction: prediction)

    expect(result).to be_success
    expect(Prediction.exists?(prediction.id)).to be(false)
  end

  it "refuses (and keeps the row) once the match is locked" do
    prediction = create(:prediction, match: create(:match, kickoff_at: 30.seconds.from_now))

    result = described_class.call(prediction: prediction)

    expect(result).to be_failure
    expect(result.errors.join).to include("cerrado")
    expect(Prediction.exists?(prediction.id)).to be(true)
  end
end
