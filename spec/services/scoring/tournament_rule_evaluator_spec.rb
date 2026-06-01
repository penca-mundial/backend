# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scoring::TournamentRuleEvaluator do
  # Pure function — build the prediction in memory, no DB.
  def evaluate(predicted:, real:)
    prediction = TournamentPrediction.new(
      champion_id: predicted[:champion], runner_up_id: predicted[:runner_up],
      third_place_id: predicted[:third], fourth_place_id: predicted[:fourth],
      top_scorer_id: predicted[:scorer]
    )
    described_class.call(
      prediction: prediction,
      champion_id: real[:champion], runner_up_id: real[:runner_up],
      third_place_id: real[:third], fourth_place_id: real[:fourth], top_scorer_id: real[:scorer]
    )
  end

  it "returns all five true when every pick matches" do
    result = evaluate(
      predicted: { champion: 1, runner_up: 2, third: 3, fourth: 4, scorer: 5 },
      real:      { champion: 1, runner_up: 2, third: 3, fourth: 4, scorer: 5 }
    )

    expect(result).to be_success
    expect(result.data).to eq(
      champion_correct: true, runner_up_correct: true, third_place_correct: true,
      fourth_place_correct: true, top_scorer_correct: true
    )
  end

  it "returns all five false when nothing matches" do
    result = evaluate(
      predicted: { champion: 1, runner_up: 2, third: 3, fourth: 4, scorer: 5 },
      real:      { champion: 6, runner_up: 7, third: 8, fourth: 9, scorer: 10 }
    )

    expect(result.data.values).to all(be(false))
  end

  it "scores each dimension independently" do
    result = evaluate(
      predicted: { champion: 1, runner_up: 2, third: 3, fourth: 4, scorer: 5 },
      real:      { champion: 1, runner_up: 99, third: 3, fourth: 99, scorer: 5 }
    )

    expect(result.data).to eq(
      champion_correct: true, runner_up_correct: false, third_place_correct: true,
      fourth_place_correct: false, top_scorer_correct: true
    )
  end

  it "treats a nil user pick as a miss even when there is a real result" do
    result = evaluate(
      predicted: { champion: nil, runner_up: 2, third: 3, fourth: 4, scorer: 5 },
      real:      { champion: 1,   runner_up: 2, third: 3, fourth: 4, scorer: 5 }
    )

    expect(result.data[:champion_correct]).to be(false)
    expect(result.data[:runner_up_correct]).to be(true)
  end

  it "treats a nil real result as a miss even when the user picked" do
    result = evaluate(
      predicted: { champion: 1,   runner_up: 2, third: 3, fourth: 4, scorer: 5 },
      real:      { champion: nil, runner_up: 2, third: 3, fourth: 4, scorer: 5 }
    )

    expect(result.data[:champion_correct]).to be(false)
  end

  it "treats nil == nil as a miss" do
    result = evaluate(
      predicted: { champion: nil, runner_up: 2, third: 3, fourth: 4, scorer: 5 },
      real:      { champion: nil, runner_up: 2, third: 3, fourth: 4, scorer: 5 }
    )

    expect(result.data[:champion_correct]).to be(false)
  end
end
