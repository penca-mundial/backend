# frozen_string_literal: true

# Computes the group-stage tables for a tournament from its own matches — the
# group composition comes from Match#group (A..L, already populated by the
# fixture sync) and the stats are derived from the FINISHED group-stage results.
# This is independent of the mirrored /standings feed (SCRUM-262): nothing here
# reads the Standing model.
#
# Returns an array of Group structs (ordered A..L), each with the ranked Row
# structs for its teams. A group whose matches are all unplayed still lists every
# team with zeroed stats, because the teams come from the fixtures, not results.
#
# Ranking (FIFA simplified for the MVP): points desc, goal difference desc,
# goals-for desc.
class GroupStandingsQuery < ApplicationQuery
  Group = Struct.new(:name, :standings, keyword_init: true)
  Row = Struct.new(
    :team, :played, :won, :drawn, :lost,
    :goals_for, :goals_against, :goal_difference, :points, :position,
    keyword_init: true
  )

  def initialize(tournament:, relation: nil)
    super(relation)
    @tournament = tournament
  end

  def call
    matches_by_group.map do |name, matches|
      Group.new(name: name, standings: standings_for(matches))
    end
  end

  private

  # Group-stage matches of this tournament that carry a group label, preloaded
  # to keep the per-team team reads N+1-free, grouped and ordered A..L.
  def matches_by_group
    base = relation || Match.all
    base
      .where(tournament: @tournament, phase: "group_stage")
      .where.not(group: [ nil, "" ])
      .includes(:home_team, :away_team)
      .group_by(&:group)
      .sort
      .to_h
  end

  # Every team in the group starts at zero; finished matches then feed the tally.
  def standings_for(matches)
    tally = teams_in(matches).index_with { |team| blank_row(team) }
    matches.select(&:status_finished?).each { |match| apply_result(tally, match) }
    ranked(tally.values)
  end

  def teams_in(matches)
    matches.flat_map { |match| [ match.home_team, match.away_team ] }.uniq
  end

  def blank_row(team)
    Row.new(
      team: team, played: 0, won: 0, drawn: 0, lost: 0,
      goals_for: 0, goals_against: 0, goal_difference: 0, points: 0, position: 0
    )
  end

  def apply_result(tally, match)
    record(tally[match.home_team], match.home_score, match.away_score)
    record(tally[match.away_team], match.away_score, match.home_score)
  end

  # Fold one team's result (its goals vs the opponent's) into its row.
  def record(row, scored, conceded)
    row.played += 1
    row.goals_for += scored
    row.goals_against += conceded
    row.goal_difference = row.goals_for - row.goals_against

    if scored > conceded
      row.won += 1
      row.points += 3
    elsif scored == conceded
      row.drawn += 1
      row.points += 1
    else
      row.lost += 1
    end
  end

  # points desc, goal difference desc, goals-for desc; position is 1-based.
  def ranked(rows)
    rows
      .sort_by { |row| [ -row.points, -row.goal_difference, -row.goals_for ] }
      .each_with_index { |row, index| row.position = index + 1 }
  end
end
