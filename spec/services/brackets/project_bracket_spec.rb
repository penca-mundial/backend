# frozen_string_literal: true

require "rails_helper"

RSpec.describe Brackets::ProjectBracket do
  let(:tournament) { create(:tournament) }
  let(:user) { create(:user) }

  # A group whose positions are deterministic (round robin, lower index wins).
  def build_group(letter, size = 4)
    teams = Array.new(size) { |i| create(:team, tournament: tournament, name: "#{letter}#{i + 1}") }
    teams.combination(2).each do |winner, loser|
      create(:match, tournament: tournament, phase: "group_stage", group: letter, status: "finished",
                     home_team: winner, away_team: loser, home_score: 1, away_score: 0)
    end
    teams
  end

  def table(slots, first_round: "round_of_16")
    Brackets::OrderTable.new(first_round: first_round, slots: slots)
  end

  def project(order_table)
    described_class.call(tournament: tournament, user: user, order_table: order_table).data
  end

  it "resolves determinate sides from projected positions; a best-third side is null" do
    a = build_group("A")
    b = build_group("B")
    res = project(table([
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "B", "position" => 2 } ] },
      { "order" => 1, "sides" => [ { "group" => "A", "position" => 2 }, { "position" => 3 } ] }
    ]))

    expect(res[:projected]).to be(true)
    slot0 = res[:round_of_32].find { |s| s[:bracket_position] == 0 }
    expect(slot0).to include(source: "projected")
    expect(slot0[:home][:id]).to eq(a[0].id) # A 1st
    expect(slot0[:away][:id]).to eq(b[1].id) # B 2nd

    slot1 = res[:round_of_32].find { |s| s[:bracket_position] == 1 }
    expect(slot1[:home][:id]).to eq(a[1].id) # A 2nd
    expect(slot1[:away]).to be_nil           # best third -> A definir
  end

  it "blends the user's prediction for an unplayed group match into the position" do
    a1 = create(:team, tournament: tournament, name: "A1")
    a2 = create(:team, tournament: tournament, name: "A2")
    match = create(:match, tournament: tournament, phase: "group_stage", group: "A", status: "scheduled",
                           home_team: a1, away_team: a2, kickoff_at: 1.week.from_now)
    create(:prediction, user: user, match: match, predicted_home_score: 0, predicted_away_score: 3)

    res = project(table([
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "A", "position" => 2 } ] }
    ]))

    slot0 = res[:round_of_32].first
    expect(slot0[:home][:id]).to eq(a2.id) # predicted 0-3 -> a2 projected 1st
    expect(slot0[:away][:id]).to eq(a1.id)
  end

  it "leaves a side null when the rank is ambiguous (tie at the boundary)" do
    a1 = create(:team, tournament: tournament, name: "A1")
    a2 = create(:team, tournament: tournament, name: "A2")
    create(:match, tournament: tournament, phase: "group_stage", group: "A", status: "finished",
                   home_team: a1, away_team: a2, home_score: 1, away_score: 1) # draw -> 1st/2nd tie

    res = project(table([
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "A", "position" => 2 } ] }
    ]))

    slot0 = res[:round_of_32].first
    expect(slot0[:home]).to be_nil
    expect(slot0[:away]).to be_nil
  end

  it "lets a real anchored match win over the projection" do
    build_group("A")
    build_group("B")
    x = create(:team, tournament: tournament, name: "Real Home")
    y = create(:team, tournament: tournament, name: "Real Away")
    create(:match, tournament: tournament, phase: "round_of_16", status: "finished", kickoff_at: 1.day.ago,
                   home_team: x, away_team: y, home_score: 1, away_score: 0, bracket_position: 0)

    res = project(table([
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "B", "position" => 2 } ] },
      { "order" => 1, "sides" => [ { "group" => "A", "position" => 2 }, { "group" => "B", "position" => 1 } ] }
    ]))

    slot0 = res[:round_of_32].find { |s| s[:bracket_position] == 0 }
    expect(slot0).to include(source: "real")
    expect(slot0[:home][:id]).to eq(x.id) # real teams, not the projected A 1st
    expect(res[:round_of_32].find { |s| s[:bracket_position] == 1 }[:source]).to eq("projected")
  end

  it "reports projected:false when every slot is a real match" do
    x = create(:team, tournament: tournament)
    y = create(:team, tournament: tournament)
    create(:match, tournament: tournament, phase: "round_of_16", status: "finished", kickoff_at: 1.day.ago,
                   home_team: x, away_team: y, home_score: 2, away_score: 1, bracket_position: 0)

    res = project(table([
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "B", "position" => 2 } ] }
    ]))

    expect(res[:projected]).to be(false)
    expect(res[:round_of_32].first[:source]).to eq("real")
  end

  it "returns an empty projection when the tournament has no curated table" do
    expect(project(nil)).to eq(projected: false, round_of_32: [])
  end
end
