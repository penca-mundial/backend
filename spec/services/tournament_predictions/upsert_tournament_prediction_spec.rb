# frozen_string_literal: true

require "rails_helper"

RSpec.describe TournamentPredictions::UpsertTournamentPrediction do
  let(:user)       { create(:user) }
  let(:tournament) { create(:tournament, starts_at: 1.week.from_now, ends_at: 5.weeks.from_now) }
  let(:team_a)     { create(:team, tournament: tournament) }
  let(:team_b)     { create(:team, tournament: tournament) }

  # Picks must PARTICIPATE (play a match), not just carry the tournament tag.
  before { create(:match, tournament: tournament, home_team: team_a, away_team: team_b, kickoff_at: 2.weeks.from_now) }

  def upsert(**overrides)
    described_class.call(user: user, tournament: tournament, **overrides)
  end

  it "creates the prediction" do
    result = nil
    expect { result = upsert(champion_id: team_a.id, runner_up_id: team_b.id) }
      .to change(TournamentPrediction, :count).by(1)

    expect(result).to be_success
    expect(result.data).to have_attributes(champion_id: team_a.id, runner_up_id: team_b.id)
  end

  it "updates the existing per-user-per-tournament prediction without duplicating it" do
    upsert(champion_id: team_a.id)

    result = nil
    expect { result = upsert(champion_id: team_b.id) }.not_to change(TournamentPrediction, :count)
    expect(result.data.reload.champion_id).to eq(team_b.id)
  end

  it "accepts partial input (champion only)" do
    expect(upsert(champion_id: team_a.id)).to be_success
  end

  it "rejects once the deadline (first kickoff - 1 minute) has passed" do
    started = create(:tournament, starts_at: 1.day.from_now, ends_at: 30.days.from_now)
    match = create(:match, tournament: started, kickoff_at: 30.seconds.from_now)

    result = described_class.call(user: user, tournament: started, champion_id: match.home_team_id)

    expect(result).to be_failure
    expect(result.errors.join).to include("cerrado")
  end

  it "allows upserting after starts_at while the first kickoff is still ahead" do
    # The real-world bug: starts_at (midnight) passed, the opener is hours away.
    open_window = create(:tournament, starts_at: 1.hour.ago, ends_at: 30.days.from_now)
    match = create(:match, tournament: open_window, kickoff_at: 6.hours.from_now)

    result = described_class.call(user: user, tournament: open_window, champion_id: match.home_team_id)

    expect(result).to be_success
  end

  it "rejects when podium teams are duplicated" do
    expect(upsert(champion_id: team_a.id, runner_up_id: team_a.id)).to be_failure
  end

  it "rejects when a team is not from the tournament" do
    outsider = create(:team) # belongs to a different tournament

    expect(upsert(champion_id: outsider.id)).to be_failure
  end

  it "rejects a team tagged to the tournament that plays no matches (seed leftover)" do
    leftover = create(:team, tournament: tournament)

    expect(upsert(champion_id: leftover.id)).to be_failure
  end
end
