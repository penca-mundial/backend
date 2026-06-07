# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserEvolutionQuery do
  let(:user) { create(:user) }
  let(:tournament) { create(:tournament) }

  def snapshot(at:, points: 10, rank: 1, group: nil, on_tournament: nil, for_user: nil)
    create(:ranking_snapshot, user: for_user || user, tournament: on_tournament || tournament,
                              group: group, snapshot_at: at, points: points, rank_position: rank)
  end

  it "returns { snapshot_at, points, rank_position } ordered chronologically (asc)" do
    snapshot(at: 1.day.ago, points: 30, rank: 1)
    snapshot(at: 3.days.ago, points: 10, rank: 5)
    snapshot(at: 2.days.ago, points: 20, rank: 3)

    result = described_class.call(user: user, tournament: tournament)

    expect(result.map { |r| r[:points] }).to eq([ 10, 20, 30 ]) # oldest -> newest
    expect(result.first.keys).to contain_exactly(:snapshot_at, :points, :rank_position)
    expect(result.last).to include(points: 30, rank_position: 1)
  end

  it "excludes snapshots older than the days window" do
    snapshot(at: 5.days.ago, points: 20)
    snapshot(at: 40.days.ago, points: 99) # outside the default 30-day window

    result = described_class.call(user: user, tournament: tournament, days: 30)

    expect(result.map { |r| r[:points] }).to eq([ 20 ])
  end

  it "returns only the given group's rows when group is set" do
    group = create(:group)
    snapshot(at: 1.day.ago, points: 50, group: group)
    snapshot(at: 1.day.ago, points: 10, group: nil)             # global, excluded
    snapshot(at: 1.day.ago, points: 99, group: create(:group)) # other group, excluded

    result = described_class.call(user: user, tournament: tournament, group: group)

    expect(result.map { |r| r[:points] }).to eq([ 50 ])
  end

  it "returns only global rows (group_id NULL) when group is nil" do
    snapshot(at: 1.day.ago, points: 10, group: nil)
    snapshot(at: 1.day.ago, points: 50, group: create(:group)) # group row, excluded

    result = described_class.call(user: user, tournament: tournament)

    expect(result.map { |r| r[:points] }).to eq([ 10 ])
  end

  it "does not mix in snapshots from another tournament" do
    other_tournament = create(:tournament)
    snapshot(at: 1.day.ago, points: 10)
    snapshot(at: 1.day.ago, points: 99, on_tournament: other_tournament) # excluded

    result = described_class.call(user: user, tournament: tournament)

    expect(result.map { |r| r[:points] }).to eq([ 10 ])
  end

  it "returns an empty array when the user has no snapshots" do
    expect(described_class.call(user: user, tournament: tournament)).to eq([])
  end
end
