# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlayersQuery do
  it "filters by team_id" do
    team = create(:team)
    keep = create(:player, team: team, name: "Aaron")
    create(:player) # other team

    expect(described_class.call(filters: { team_id: team.id })).to eq([ keep ])
  end

  it "filters by tournament_id through the player's team" do
    tournament = create(:tournament)
    team_a = create(:team, tournament: tournament)
    team_b = create(:team, tournament: tournament)
    p1 = create(:player, team: team_a, name: "Aaron")
    p2 = create(:player, team: team_b, name: "Zoe")
    create(:player) # another tournament

    expect(described_class.call(filters: { tournament_id: tournament.id })).to eq([ p1, p2 ])
  end

  it "orders by name and preloads team" do
    team = create(:team)
    create(:player, team: team, name: "Zoe")
    create(:player, team: team, name: "Aaron")

    result = described_class.call(filters: { team_id: team.id }).to_a

    expect(result.map(&:name)).to eq(%w[Aaron Zoe])
    expect(result.first.association(:team)).to be_loaded
  end

  it "breaks ties on id so the order is total (stable across paginated pages)" do
    team = create(:team)
    # Same name, inserted out of id order — ordering must fall back to id asc.
    third  = create(:player, team: team, name: "Lionel Messi")
    first  = create(:player, team: team, name: "Lionel Messi")
    second = create(:player, team: team, name: "Lionel Messi")
    # Reassign ids notionally: whatever the create order, expectation is id asc.
    expected = [ third, first, second ].sort_by(&:id)

    result = described_class.call(filters: { team_id: team.id }).to_a

    expect(result).to eq(expected)
    expect(result.map(&:id)).to eq(result.map(&:id).sort)
  end
end
