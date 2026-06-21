# frozen_string_literal: true

require "rails_helper"

# Verifies the OFFICIAL db/seeds/data/brackets/wc.yml against the FIFA 2026 tree:
# the builder, run over a simulated full Round-of-32, must order R32 vertically so
# that the two matches feeding the same R16 are adjacent (positions 2k / 2k+1),
# and each R16 lands at position k.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "FIFA 2026 bracket (wc.yml)" do
  # rubocop:enable RSpec/DescribeClass
  let(:tournament) { create(:tournament, external_code: "WC") }

  # Builds the full simulated bracket, runs the builder (auto-loads wc.yml), and
  # returns the R32/R16 match records by FIFA number.
  let(:bracket) do
    groups = ("A".."L").to_h { |letter| [ letter, build_group(letter) ] }
    r32 = r32_defs.transform_values do |(home, away)|
      ko("round_of_32", team_for(home, groups), team_for(away, groups))
    end
    r16 = r16_defs.transform_values do |(home, away)|
      ko("round_of_16", r32[home].advancing_team, r32[away].advancing_team)
    end

    Brackets::BuildTopology.call(tournament: tournament) # auto-loads wc.yml
    { r32: r32, r16: r16 }
  end

  # R32 matchups as drawn (home side first). "t:X" = the best third placed in this
  # slot, taken from group X's 3rd place (its identity is irrelevant to the ORDER;
  # only position 3 matters for anchoring).
  def r32_defs
    { 73 => %w[A2 B2], 74 => %w[E1 t:A], 75 => %w[F1 C2], 76 => %w[C1 F2],
      77 => %w[I1 t:B], 78 => %w[E2 I2], 79 => %w[A1 t:C], 80 => %w[L1 t:D],
      81 => %w[D1 t:E], 82 => %w[G1 t:F], 83 => %w[K2 L2], 84 => %w[H1 J2],
      85 => %w[B1 t:G], 86 => %w[J1 H2], 87 => %w[K1 t:H], 88 => %w[D2 G2] }
  end

  # R16 = winner(home feeder) vs winner(away feeder).
  def r16_defs
    { 89 => [ 74, 77 ], 90 => [ 73, 75 ], 91 => [ 76, 78 ], 92 => [ 79, 80 ],
      93 => [ 83, 84 ], 94 => [ 81, 82 ], 95 => [ 86, 88 ], 96 => [ 85, 87 ] }
  end

  # The vertical order the tree dictates (and that wc.yml must reproduce).
  def expected_r32
    { 74 => 0, 77 => 1, 73 => 2, 75 => 3, 83 => 4, 84 => 5, 81 => 6, 82 => 7,
      76 => 8, 78 => 9, 79 => 10, 80 => 11, 86 => 12, 88 => 13, 85 => 14, 87 => 15 }
  end

  def expected_r16
    { 89 => 0, 90 => 1, 93 => 2, 94 => 3, 91 => 4, 92 => 5, 95 => 6, 96 => 7 }
  end

  # A group of four whose positions are 1..4 (round robin, lower index wins).
  def build_group(letter)
    teams = Array.new(4) { |i| create(:team, tournament: tournament, name: "#{letter}#{i + 1}") }
    teams.combination(2).each do |winner, loser|
      create(:match, tournament: tournament, phase: "group_stage", group: letter, status: "finished",
                     home_team: winner, away_team: loser, home_score: 1, away_score: 0)
    end
    teams
  end

  def team_for(token, groups)
    return groups.fetch(token[2])[2] if token.start_with?("t:") # 3rd place

    groups.fetch(token[0])[token[1].to_i - 1]
  end

  def ko(phase, home, away)
    create(:match, tournament: tournament, phase: phase, status: "finished",
                   home_team: home, away_team: away, kickoff_at: 1.day.ago,
                   home_score: 1, away_score: 0, advancing_team_id: home.id) # home advances
  end

  it "anchors every R32 match to its tree-derived vertical position" do
    expected_r32.each do |number, position|
      expect(bracket[:r32][number].reload.bracket_position).to eq(position), "R32 M#{number}"
    end
  end

  it "places the two R32 feeders of each R16 adjacent (2k / 2k+1) and pointing at it" do
    r16_defs.each do |r16_number, (home_feeder, away_feeder)|
      k = expected_r16.fetch(r16_number)
      home = bracket[:r32][home_feeder].reload
      away = bracket[:r32][away_feeder].reload

      expect([ home.bracket_position, away.bracket_position ]).to contain_exactly(2 * k, 2 * k + 1)
      expect(home.feeds_into_match_id).to eq(bracket[:r16][r16_number].id)
      expect(away.feeds_into_match_id).to eq(bracket[:r16][r16_number].id)
    end
  end

  it "positions each R16 at its tree index (home parent / 2)" do
    expected_r16.each do |number, position|
      expect(bracket[:r16][number].reload.bracket_position).to eq(position), "R16 M#{number}"
    end
  end

  it "anchors all 16 slots with no reconciliation warning" do
    bracket # build + first run
    expect(Rails.logger).not_to receive(:warn)
    Brackets::BuildTopology.call(tournament: tournament)
  end
end
