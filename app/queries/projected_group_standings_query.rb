# frozen_string_literal: true

# Computes the group-stage tables PROJECTED for one user: the official tables
# (GroupStandingsQuery, ADR 0002) where every group match not yet finished is
# filled in with that user's own prediction. The blend, per match:
#
#   * finished                          -> official result (everything counts)
#   * not finished, the user predicted  -> predicted score (goals/points ONLY)
#   * not finished, no prediction       -> excluded entirely
#
# Played/won/drawn/lost stay strictly official — a deliberate hybrid (ADR 0005):
# pre-tournament the table shows 0 played yet a fully projected ranking, and as
# real results land they replace the predictions, so the table converges to the
# official one. Ranking is the parent's criteria (points desc, goal difference
# desc, goals-for desc) applied over the blended values.
class ProjectedGroupStandingsQuery < GroupStandingsQuery
  def initialize(tournament:, user:, relation: nil)
    super(tournament: tournament, relation: relation)
    @user = user
  end

  private

  # Same tally as the parent, blending the user's predictions in for matches
  # that have not finished yet.
  def standings_for(matches)
    tally = teams_in(matches).index_with { |team| blank_row(team) }
    matches.each do |match|
      if match.status_finished?
        apply_result(tally, match)
      elsif (prediction = predictions_by_match_id[match.id])
        apply_prediction(tally, match, prediction)
      end
    end
    ranked(tally.values)
  end

  def apply_prediction(tally, match, prediction)
    project(tally[match.home_team], prediction.predicted_home_score, prediction.predicted_away_score)
    project(tally[match.away_team], prediction.predicted_away_score, prediction.predicted_home_score)
  end

  # Fold one team's predicted score into its row: goals and points only — the
  # match counters (played/won/drawn/lost) are official-only on purpose.
  def project(row, scored, conceded)
    row.goals_for += scored
    row.goals_against += conceded
    row.goal_difference = row.goals_for - row.goals_against
    row.points +=
      if scored > conceded
        3
      elsif scored == conceded
        1
      else
        0
      end
  end

  # The user's predictions for every group-stage match, fetched once (the
  # parent memoizes matches_by_group, so this adds a single extra query).
  def predictions_by_match_id
    @predictions_by_match_id ||= Prediction
      .where(user: @user, match_id: matches_by_group.values.flatten.map(&:id))
      .index_by(&:match_id)
  end
end
