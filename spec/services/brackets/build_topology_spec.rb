# frozen_string_literal: true

require "rails_helper"

RSpec.describe Brackets::BuildTopology do
  let(:tournament) { create(:tournament, external_code: "DEMO") }

  # A group of `size` teams whose final positions are deterministic: a round
  # robin where the lower index always beats the higher (teams[0] wins all ->
  # position 1, teams[1] -> 2, ...). Returns the teams in position order.
  def build_group(letter, size = 4)
    teams = Array.new(size) { |i| create(:team, tournament: tournament, name: "#{letter}#{i + 1}") }
    teams.combination(2).each do |winner, loser|
      create(:match, tournament: tournament, phase: "group_stage", group: letter, status: "finished",
                     home_team: winner, away_team: loser, home_score: 1, away_score: 0)
    end
    teams
  end

  # A knockout match; the advancing team defaults to the home side.
  def ko(phase, home, away, advancing: home)
    create(:match, tournament: tournament, phase: phase, status: "finished",
                   home_team: home, away_team: away, kickoff_at: 1.day.ago,
                   home_score: 1, away_score: 0, advancing_team_id: advancing&.id)
  end

  # First round = quarter_final (8 teams, 2 groups). One slot per third place to
  # exercise the "vs best third" anchoring. Canonical order 0..3.
  def order_table
    Brackets::OrderTable.new(slots: [
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "B", "position" => 2 } ] },
      { "order" => 1, "sides" => [ { "group" => "B", "position" => 1 }, { "group" => "A", "position" => 2 } ] },
      { "order" => 2, "sides" => [ { "position" => 3 }, { "group" => "B", "position" => 4 } ] },
      { "order" => 3, "sides" => [ { "position" => 3 }, { "group" => "A", "position" => 4 } ] }
    ])
  end

  # Builds the full small bracket and returns the match records by handle.
  def build_bracket
    a = build_group("A")
    b = build_group("B")

    qf0 = ko("quarter_final", a[0], b[1], advancing: a[0]) # A1 vs B2
    qf1 = ko("quarter_final", b[0], a[1], advancing: b[0]) # B1 vs A2
    qf2 = ko("quarter_final", a[2], b[3], advancing: a[2]) # A3 (third) vs B4
    qf3 = ko("quarter_final", b[2], a[3], advancing: b[2]) # B3 (third) vs A4

    sf0 = ko("semi_final", a[0], b[0], advancing: a[0]) # winners qf0, qf1
    sf1 = ko("semi_final", a[2], b[2], advancing: a[2]) # winners qf2, qf3
    final = ko("final", a[0], a[2], advancing: a[0])     # winners sf0, sf1
    ko("third_place", b[0], b[2])                        # sf losers (a sink)

    { qf0:, qf1:, qf2:, qf3:, sf0:, sf1:, final: }
  end

  def run
    described_class.call(tournament: tournament, order_table: order_table)
  end

  describe "feeds_into edges (from advancing_team)" do
    it "wires each parent to the next-round match its advancing team plays in, with the right slot" do
      m = build_bracket

      run

      expect(m[:qf0].reload).to have_attributes(feeds_into_match_id: m[:sf0].id, feeds_into_slot: "home")
      expect(m[:qf1].reload).to have_attributes(feeds_into_match_id: m[:sf0].id, feeds_into_slot: "away")
      expect(m[:qf2].reload).to have_attributes(feeds_into_match_id: m[:sf1].id, feeds_into_slot: "home")
      expect(m[:qf3].reload).to have_attributes(feeds_into_match_id: m[:sf1].id, feeds_into_slot: "away")
      expect(m[:sf0].reload).to have_attributes(feeds_into_match_id: m[:final].id, feeds_into_slot: "home")
      expect(m[:sf1].reload).to have_attributes(feeds_into_match_id: m[:final].id, feeds_into_slot: "away")
    end

    it "leaves the final (a sink) without a feeds_into edge" do
      m = build_bracket
      run
      expect(m[:final].reload.feeds_into_match_id).to be_nil
    end

    it "does not wire a parent whose advancing team is not yet known" do
      m = build_bracket
      m[:qf0].update!(advancing_team_id: nil)

      run

      expect(m[:qf0].reload.feeds_into_match_id).to be_nil
    end
  end

  describe "bracket_position" do
    it "anchors the first round to the curated canonical order (incl. third-place slots)" do
      m = build_bracket
      run

      expect(m[:qf0].reload.bracket_position).to eq(0)
      expect(m[:qf1].reload.bracket_position).to eq(1)
      expect(m[:qf2].reload.bracket_position).to eq(2) # A3 third anchored by the B4 side
      expect(m[:qf3].reload.bracket_position).to eq(3) # B3 third anchored by the A4 side
    end

    it "propagates later rounds from each match's home-slot parent (parent / 2)" do
      m = build_bracket
      run

      expect(m[:sf0].reload.bracket_position).to eq(0) # home parent qf0 (0) / 2
      expect(m[:sf1].reload.bracket_position).to eq(1) # home parent qf2 (2) / 2
      expect(m[:final].reload.bracket_position).to eq(0) # home parent sf0 (0) / 2
    end
  end

  describe "idempotency" do
    it "persists nothing on a second run over an unchanged fixture" do
      build_bracket

      first = run
      expect(first.data[:edges] + first.data[:positions]).to be > 0

      second = run
      expect(second.data).to eq(edges: 0, positions: 0)
    end
  end

  describe "reconciliation (visible, non-silent)" do
    it "warns and skips a first-round match whose positions fit no slot" do
      a = build_group("A")
      b = build_group("B")
      # A1 vs A2 fits none of the slots (no slot pairs two same-group teams).
      odd = ko("quarter_final", a[0], a[1], advancing: a[0])

      expect(Rails.logger).to receive(:warn).with(/could not anchor .* #{odd.external_id}/)

      run

      expect(odd.reload.bracket_position).to be_nil
    end
  end

  describe "auto-loading the curated table by external_code" do
    it "reads db/seeds/data/brackets/demo.yml when no table is injected" do
      m = build_bracket

      described_class.call(tournament: tournament) # :auto -> OrderTable.from_file("DEMO")

      expect(m[:qf0].reload.bracket_position).to eq(0)
      expect(m[:qf2].reload.bracket_position).to eq(2)
    end
  end

  describe "without a curated table" do
    it "wires edges but leaves bracket_position untouched" do
      m = build_bracket

      result = described_class.call(tournament: tournament, order_table: nil)

      expect(m[:qf0].reload.feeds_into_match_id).to eq(m[:sf0].id) # edges still built
      expect(m[:qf0].reload.bracket_position).to be_nil            # positions skipped
      expect(result.data[:positions]).to eq(0)
    end
  end
end
