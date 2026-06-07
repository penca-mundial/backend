# frozen_string_literal: true

require "rails_helper"

RSpec.describe Scoring::ComputeTournamentScores do
  let(:tournament) { create(:tournament, external_code: "WC") }
  let(:client)     { instance_double(FootballData::Client) }
  let(:teams) do
    %i[champion runner_up third fourth].index_with { create(:team, tournament: tournament) }
  end
  let(:scorer) { create(:player, team: teams[:champion], external_id: "999") }

  before do
    { champion_correct: 50, runner_up_correct: 30, third_place_correct: 20,
      fourth_place_correct: 10, top_scorer_correct: 25 }.each do |rule_type, points|
      ScoringRule.create!(rule_type: rule_type, points: points)
    end
    allow(client).to receive(:scorers).and_return("scorers" => [ { "player" => { "id" => 999 } } ])
  end

  # Finished final (champion beats runner_up) and third-place match (third beats fourth).
  def finish_podium
    create(:match, :final, tournament: tournament,
                           home_team: teams[:champion], away_team: teams[:runner_up],
                           status: "finished", advancing_team: teams[:champion])
    create(:match, :third_place, tournament: tournament,
                                 home_team: teams[:third], away_team: teams[:fourth],
                                 status: "finished", advancing_team: teams[:third])
  end

  def run
    described_class.call(tournament: tournament, client: client)
  end

  it "scores a fully-correct prediction (no multiplier) and totals it" do
    finish_podium
    scorer
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user),
                        champion: teams[:champion], runner_up: teams[:runner_up],
                        third_place: teams[:third], fourth_place: teams[:fourth], top_scorer: scorer)

    result = run

    expect(result).to be_success
    expect(result.data).to eq(count: 1)
    expect(prediction.reload.tournament_prediction_score).to have_attributes(
      points_champion: 50, points_runner_up: 30, points_third: 20,
      points_fourth: 10, points_top_scorer: 25, total_points: 135
    )
  end

  it "resolves runner_up and fourth as the losers of the final and third-place match" do
    finish_podium
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user),
                        runner_up: teams[:runner_up], fourth_place: teams[:fourth])

    run

    expect(prediction.reload.tournament_prediction_score).to have_attributes(
      points_runner_up: 30, points_fourth: 10, points_champion: 0, total_points: 40
    )
  end

  it "awards no podium points when the source match is missing or unfinished" do
    # Only the final is finished; there is no third-place match. The picked team
    # still participates (a group-stage match) so the prediction itself is valid.
    create(:match, :final, tournament: tournament, home_team: teams[:champion], away_team: teams[:runner_up],
                           status: "finished", advancing_team: teams[:champion])
    create(:match, tournament: tournament, home_team: teams[:third], away_team: teams[:fourth])
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user),
                        champion: teams[:champion], third_place: teams[:third])

    run

    expect(prediction.reload.tournament_prediction_score).to have_attributes(points_champion: 50, points_third: 0)
  end

  it "awards no champion points when the final has no advancing team" do
    create(:match, :final, tournament: tournament, home_team: teams[:champion], away_team: teams[:runner_up],
                           status: "finished", advancing_team: nil)
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user),
                        champion: teams[:champion])

    run

    expect(prediction.reload.tournament_prediction_score.points_champion).to eq(0)
  end

  it "maps the leading scorer to our Player and awards the points" do
    finish_podium
    scorer
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user), top_scorer: scorer)

    run

    expect(prediction.reload.tournament_prediction_score.points_top_scorer).to eq(25)
  end

  it "treats an empty/unmapped leading scorer as a miss" do
    finish_podium
    allow(client).to receive(:scorers).and_return("scorers" => []) # no leader resolved
    other = create(:player, team: teams[:champion])
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user), top_scorer: other)

    run

    expect(prediction.reload.tournament_prediction_score.points_top_scorer).to eq(0)
  end

  it "skips the scorers fetch when the tournament has no external_code" do
    tournament.update!(external_code: nil)
    finish_podium
    create(:tournament_prediction, tournament: tournament, user: create(:user), champion: teams[:champion])

    run

    expect(client).not_to have_received(:scorers)
  end

  it "is idempotent: re-running upserts the same values without duplicating" do
    finish_podium
    prediction = create(:tournament_prediction, tournament: tournament, user: create(:user), champion: teams[:champion])

    run
    expect { run }.not_to change(TournamentPredictionScore, :count)
    expect(prediction.reload.tournament_prediction_score.points_champion).to eq(50)
  end

  it "persists the resolved podium and top scorer on the tournament" do
    finish_podium
    scorer

    run

    expect(tournament.reload).to have_attributes(
      champion_id: teams[:champion].id, runner_up_id: teams[:runner_up].id,
      third_place_id: teams[:third].id, fourth_place_id: teams[:fourth].id,
      top_scorer_id: scorer.id
    )
  end

  it "leaves unresolved tournament columns nil when a source match is missing" do
    # Only the final is finished; no third-place match and no top scorer resolved.
    create(:match, :final, tournament: tournament, home_team: teams[:champion], away_team: teams[:runner_up],
                           status: "finished", advancing_team: teams[:champion])
    allow(client).to receive(:scorers).and_return("scorers" => [])

    run

    expect(tournament.reload).to have_attributes(
      champion_id: teams[:champion].id, runner_up_id: teams[:runner_up].id,
      third_place_id: nil, fourth_place_id: nil, top_scorer_id: nil
    )
  end

  it "is idempotent on the tournament columns when re-run" do
    finish_podium
    scorer
    result_columns = %w[champion_id runner_up_id third_place_id fourth_place_id top_scorer_id]

    run
    expect { run }.not_to change { tournament.reload.attributes.slice(*result_columns) }
  end
end
