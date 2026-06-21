# frozen_string_literal: true

# Seed (b): a COMPLETE simulated knockout bracket for end-to-end preview/testing
# of the bracket drawing — a self-contained tournament (external_code "DEMO")
# with groups, finished group results, and every knockout match (teams, scores,
# advancing teams, winners) already resolved, then wired by Brackets::BuildTopology.
#
# NOT part of db/seeds.rb (it must never touch the real World Cup tournament).
# Load it explicitly:  bin/rails bracket:demo   (or runner on this file).
#
# Idempotent: tournament by external_code, teams by code3, matches by external_id.
module Seeds
  module BracketsDemo
    CODE = "DEMO"
    GROUPS = %w[A B].freeze
    GROUP_SIZE = 4

    module_function

    def call
      tournament = upsert_tournament
      teams = GROUPS.index_with { |letter| build_group(tournament, letter) }
      seed_group_results(tournament, teams)
      seed_knockout(tournament, teams)

      result = ::Brackets::BuildTopology.call(tournament: tournament)
      { tournament_id: tournament.id, edges: result.data[:edges], positions: result.data[:positions] }
    end

    def upsert_tournament
      ::Tournament.find_or_initialize_by(external_code: CODE).tap do |t|
        t.name ||= "Bracket Demo"
        t.starts_at ||= Time.current.beginning_of_day
        t.ends_at ||= 1.month.from_now
        t.save!
      end
    end

    # Four teams per group, named <letter>1..<letter>4 in final-position order.
    def build_group(tournament, letter)
      (1..GROUP_SIZE).map do |i|
        code = "D#{letter}#{i}"
        ::Team.find_or_initialize_by(external_id: "demo-team-#{code.downcase}").tap do |team|
          team.tournament = tournament
          team.code3 = code
          team.name = "#{letter}#{i}"
          team.save!
        end
      end
    end

    # Round robin where the lower index always wins, so positions are 1..4.
    def seed_group_results(tournament, teams)
      teams.each do |letter, group|
        group.combination(2).each do |winner, loser|
          upsert_match(tournament, "demo-grp-#{winner.code3}-#{loser.code3}",
                       phase: "group_stage", group: letter, home_team: winner, away_team: loser,
                       home_score: 1, away_score: 0)
        end
      end
    end

    def seed_knockout(tournament, teams)
      a = teams.fetch("A")
      b = teams.fetch("B")

      qf0 = knockout(tournament, "qf0", "quarter_final", a[0], b[1]) # A1 vs B2
      qf1 = knockout(tournament, "qf1", "quarter_final", b[0], a[1]) # B1 vs A2
      qf2 = knockout(tournament, "qf2", "quarter_final", a[2], b[3]) # A3 (third) vs B4
      qf3 = knockout(tournament, "qf3", "quarter_final", b[2], a[3]) # B3 (third) vs A4

      sf0 = knockout(tournament, "sf0", "semi_final", a[0], b[0]) # winners qf0, qf1
      sf1 = knockout(tournament, "sf1", "semi_final", a[2], b[2]) # winners qf2, qf3
      knockout(tournament, "final", "final", a[0], a[2])          # winners sf0, sf1
      knockout(tournament, "third", "third_place", b[0], b[2], advancing: nil) # sf losers (sink)

      [ qf0, qf1, qf2, qf3, sf0, sf1 ] # (returned for symmetry; unused)
    end

    # A finished KO match; the home team advances unless told otherwise.
    def knockout(tournament, slug, phase, home, away, advancing: :home)
      winner = advancing == :home ? home : advancing
      upsert_match(tournament, "demo-#{slug}", phase: phase, group: nil,
                   home_team: home, away_team: away, home_score: 1, away_score: 0,
                   advancing_team_id: winner&.id)
    end

    def upsert_match(tournament, external_id, **attrs)
      ::Match.find_or_initialize_by(external_id: external_id).tap do |match|
        match.assign_attributes(tournament: tournament, status: "finished",
                                kickoff_at: 1.day.ago, **attrs)
        match.save!
      end
    end
  end
end
