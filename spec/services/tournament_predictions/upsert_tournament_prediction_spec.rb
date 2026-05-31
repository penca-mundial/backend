# frozen_string_literal: true

require "rails_helper"

RSpec.describe TournamentPredictions::UpsertTournamentPrediction do
  let(:user)       { create(:user) }
  let(:tournament) { create(:tournament, starts_at: 1.week.from_now, ends_at: 5.weeks.from_now) }
  let(:team_a)     { create(:team, tournament: tournament) }
  let(:team_b)     { create(:team, tournament: tournament) }

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

  it "rejects when the tournament has already started" do
    started = create(:tournament, starts_at: 1.day.ago, ends_at: 30.days.from_now)
    champion = create(:team, tournament: started)

    result = described_class.call(user: user, tournament: started, champion_id: champion.id)

    expect(result).to be_failure
    expect(result.errors.join).to include("cerrado")
  end

  it "rejects when podium teams are duplicated" do
    expect(upsert(champion_id: team_a.id, runner_up_id: team_a.id)).to be_failure
  end

  it "rejects when a team is not from the tournament" do
    outsider = create(:team) # belongs to a different tournament

    expect(upsert(champion_id: outsider.id)).to be_failure
  end
end
