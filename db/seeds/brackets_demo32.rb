# frozen_string_literal: true

# Preview seed: a COMPLETE 32-team knockout bracket (external_code "DEMO32") for
# visually validating the full tree in the frontend (SCRUM-317) — round_of_32
# (dieciseisavos) → round_of_16 → quarter_final → semi_final → final + third
# place, every match resolved (teams, scores, advancing teams, winners), then
# wired by Brackets::BuildTopology (feeds_into + bracket_position).
#
# 8 groups (A-H) of 4; all four of each group advance into the round_of_32 (a
# preview convenience — realism is not the point). The home team always wins, so
# advancing_team is deterministic.
#
# NOT part of db/seeds.rb (never touches the real World Cup nor the 8-team DEMO).
# Load it explicitly:  bin/rails bracket:demo32
#
# Idempotent: tournament by external_code, teams by external_id, matches by
# external_id.
module Seeds
  module BracketsDemo32
    CODE = "DEMO32"
    GROUPS = %w[A B C D E F G H].freeze
    GROUP_SIZE = 4

    # Round-of-32 pairings ("home:away", token = <Group><position>), in canonical
    # vertical order — MUST match db/seeds/data/brackets/demo32.yml. Covers all 32
    # (group, position) combinations exactly once.
    R32 = %w[
      A1:B2 C1:D2 E1:F2 G1:H2
      A2:B1 C2:D1 E2:F1 G2:H1
      A3:B4 C3:D4 E3:F4 G3:H4
      A4:B3 C4:D3 E4:F3 G4:H3
    ].freeze

    module_function

    def call
      tournament = upsert_tournament
      teams = GROUPS.index_with { |letter| build_group(tournament, letter) }

      r32 = build_round_of_32(tournament, teams)
      r16 = build_round(tournament, "round_of_16", "r16", r32)
      qf  = build_round(tournament, "quarter_final", "qf", r16)
      sf  = build_round(tournament, "semi_final", "sf", qf)
      build_round(tournament, "final", "final", sf)
      build_third_place(tournament, sf)

      result = ::Brackets::BuildTopology.call(tournament: tournament)
      { tournament_id: tournament.id, edges: result.data[:edges], positions: result.data[:positions] }
    end

    def upsert_tournament
      ::Tournament.find_or_initialize_by(external_code: CODE).tap do |t|
        t.name ||= "Bracket Demo 32"
        t.starts_at ||= Time.current.beginning_of_day
        t.ends_at ||= 1.month.from_now
        t.save!
      end
    end

    # Four teams per group in final-position order (round robin, lower index wins).
    def build_group(tournament, letter)
      teams = (1..GROUP_SIZE).map do |pos|
        upsert_team(tournament, letter, pos)
      end
      teams.combination(2).each do |winner, loser|
        upsert_match(tournament, "demo32-grp-#{winner.code3}-#{loser.code3}",
                     phase: "group_stage", group: letter, home_team: winner, away_team: loser,
                     home_score: 1, away_score: 0)
      end
      teams
    end

    def upsert_team(tournament, letter, pos)
      ::Team.find_or_initialize_by(external_id: "demo32-team-#{letter}#{pos}").tap do |team|
        team.tournament = tournament
        team.code3 = format("%s0%d", letter, pos) # e.g. A01..H04
        team.name = "#{letter}#{pos}"
        team.save!
      end
    end

    def build_round_of_32(tournament, teams)
      R32.each_with_index.map do |pairing, i|
        home_token, away_token = pairing.split(":")
        knockout(tournament, "r32-#{i}", "round_of_32", team_for(home_token, teams), team_for(away_token, teams))
      end
    end

    # Each next-round match pairs the winners of two adjacent parents.
    def build_round(tournament, phase, prefix, parents)
      parents.each_slice(2).with_index.map do |(home_parent, away_parent), i|
        knockout(tournament, "#{prefix}-#{i}", phase, home_parent.advancing_team, away_parent.advancing_team)
      end
    end

    # Third place: the two semi-final LOSERS (the away side, since home advances).
    def build_third_place(tournament, semis)
      knockout(tournament, "third", "third_place", semis[0].away_team, semis[1].away_team, advancing: nil)
    end

    def team_for(token, teams)
      teams.fetch(token[0])[token[1].to_i - 1]
    end

    # A finished knockout match; the home team advances unless told otherwise.
    def knockout(tournament, slug, phase, home, away, advancing: :home)
      winner = advancing == :home ? home : advancing
      upsert_match(tournament, "demo32-#{slug}", phase: phase, group: nil,
                   home_team: home, away_team: away, home_score: 2, away_score: 1,
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
