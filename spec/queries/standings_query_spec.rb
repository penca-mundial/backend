# frozen_string_literal: true

require "rails_helper"

RSpec.describe StandingsQuery do
  let(:tournament) { create(:tournament) }

  it "returns only the requested tournament's standings, ordered by group then position" do
    b1 = create(:standing, tournament: tournament, group: "B", position: 1)
    a2 = create(:standing, tournament: tournament, group: "A", position: 2)
    a1 = create(:standing, tournament: tournament, group: "A", position: 1)
    create(:standing) # a different tournament's standing

    expect(described_class.call(tournament: tournament)).to eq([ a1, a2, b1 ])
  end

  it "preloads the team association to avoid an N+1" do
    create(:standing, tournament: tournament)

    records = described_class.call(tournament: tournament).to_a

    expect(records.first.association(:team)).to be_loaded
  end
end
