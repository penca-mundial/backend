# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamsQuery do
  it "returns only the given tournament's teams, ordered by name" do
    tournament = create(:tournament)
    zambia = create(:team, tournament: tournament, name: "Zambia")
    argentina = create(:team, tournament: tournament, name: "Argentina")
    create(:team) # another tournament — must not leak in

    expect(described_class.call(tournament: tournament)).to eq([ argentina, zambia ])
  end
end
