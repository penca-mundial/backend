# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamsQuery do
  it "returns only teams that play in the tournament's fixture, ordered by name" do
    tournament = create(:tournament)
    zambia = create(:team, tournament: tournament, name: "Zambia")
    argentina = create(:team, tournament: tournament, name: "Argentina")
    create(:match, tournament: tournament, home_team: zambia, away_team: argentina)
    create(:team, tournament: tournament, name: "Leftover") # tagged but plays no match
    create(:team) # another tournament — must not leak in

    expect(described_class.call(tournament: tournament)).to eq([ argentina, zambia ])
  end
end
