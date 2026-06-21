# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/brackets_demo")

# Seed (b): the simulated bracket loads and wires end-to-end, and is idempotent.
RSpec.describe Seeds::BracketsDemo do
  describe ".call" do
    it "builds a complete, wired demo bracket" do
      summary = described_class.call

      tournament = Tournament.find(summary[:tournament_id])
      expect(tournament.external_code).to eq("DEMO")

      qf0 = tournament.matches.find_by!(external_id: "demo-qf0")
      sf0 = tournament.matches.find_by!(external_id: "demo-sf0")
      final = tournament.matches.find_by!(external_id: "demo-final")

      # Edges wired from advancing_team, first round anchored, positions propagated.
      expect(qf0).to have_attributes(feeds_into_match_id: sf0.id, feeds_into_slot: "home", bracket_position: 0)
      expect(sf0.reload).to have_attributes(feeds_into_match_id: final.id, bracket_position: 0)
      expect(final.reload.bracket_position).to eq(0)
    end

    it "is idempotent: re-loading neither duplicates rows nor re-wires" do
      described_class.call
      counts = -> { [ Tournament.count, Team.count, Match.count ] }
      before_counts = counts.call

      second = described_class.call

      expect(counts.call).to eq(before_counts)        # no duplicates
      expect(second).to include(edges: 0, positions: 0) # nothing re-written
    end
  end
end
