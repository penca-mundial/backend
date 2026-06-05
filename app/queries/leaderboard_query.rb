# frozen_string_literal: true

# Ranked leaderboard for a group (or, with group: nil, every user — the Phase 7
# global path; here it is always called with a group).
#
# points        = SUM(prediction_scores.total_points)            (per-match scores)
#               + SUM(tournament_prediction_scores.total_points) (the one tournament prediction)
#   Members are LEFT JOINed to the scores, so a member with no scores appears with
#   points 0 (day-1 everyone ties at 0 instead of being excluded).
# exact_count   = number of finished-match predictions that nailed the exact score
#   (breakdown->>'result_rule' = 'exact_score' — the value Scoring::ComputeMatchScores
#   writes; see Scoring::MatchRuleEvaluator).
# rank_position = RANK() OVER (points DESC, exact_count DESC) — ties SHARE a
#   position (1,1,1,4), not 1,2,3,4.
#
# Tiebreakers: points, then exact_count. A third "sum of goal differences"
# tiebreaker is intentionally NOT implemented — there is no clean stored source
# for it (the breakdown carries only the rule symbols, not the predicted/real
# margins), so remaining ties share a rank (SCRUM-149).
#
# Raw SQL: the window function over a multi-source LEFT-JOIN aggregation is
# clearer as SQL than as an AR chain. Results are cached briefly (shorter while a
# match is live); a cache hit does not touch the database.
class LeaderboardQuery < ApplicationQuery
  LIVE_TTL = 30.seconds
  IDLE_TTL = 5.minutes
  DEFAULT_LIMIT = 100
  NEIGHBORS = 2 # rows shown above/below the user in #position_of

  Row = Struct.new(
    :user_id, :username, :avatar_url, :points, :exact_count, :rank_position,
    keyword_init: true
  )

  # The ranked rows (cached). group: nil ranks every user.
  def call(group: nil, limit: DEFAULT_LIMIT)
    key = [ "leaderboard", group&.id, limit ]
    cached = Rails.cache.read(key)
    return cached if cached

    rows = run(leaderboard_sql(group), binds(group, limit: limit))
    Rails.cache.write(key, rows, expires_in: ttl)
    rows
  end

  # The user's row plus up to NEIGHBORS rows above and below it (a small context
  # window). Empty when the user is outside the universe (e.g. not a member).
  # Not cached — it is a targeted lookup, not the hot list.
  def position_of(user, group: nil)
    run(window_sql(group), binds(group, user_id: user.id))
  end

  private

  def run(sql, bindings)
    result = ApplicationRecord.connection.exec_query(ApplicationRecord.sanitize_sql([ sql, bindings ]))
    result.map do |row|
      Row.new(
        user_id:       row["user_id"],
        username:      row["username"],
        avatar_url:    row["avatar_url"],
        points:        row["points"].to_i,
        exact_count:   row["exact_count"].to_i,
        rank_position: row["rank_position"].to_i
      )
    end
  end

  # Named binds; group_id only when scoping to a group.
  def binds(group, **extra)
    (group ? { group_id: group.id } : {}).merge(extra)
  end

  # Reuse the existing "is anything live?" signal (cf. MatchesController).
  def ttl
    Match.status_live.exists? ? LIVE_TTL : IDLE_TTL
  end

  def leaderboard_sql(group)
    <<~SQL.squish
      #{ranked_cte(group)}
      SELECT user_id, username, avatar_url, points, exact_count, rank_position
      FROM ranked
      ORDER BY row_number
      LIMIT :limit
    SQL
  end

  def window_sql(group)
    <<~SQL.squish
      #{ranked_cte(group)},
      target AS (SELECT row_number AS rn FROM ranked WHERE user_id = :user_id)
      SELECT r.user_id, r.username, r.avatar_url, r.points, r.exact_count, r.rank_position
      FROM ranked r
      JOIN target t ON r.row_number BETWEEN t.rn - #{NEIGHBORS} AND t.rn + #{NEIGHBORS}
      ORDER BY r.row_number
    SQL
  end

  # The shared CTE: the member universe LEFT JOINed to the two score sources,
  # with RANK() for display (shared ties) and ROW_NUMBER() for stable ordering
  # and the position_of window.
  def ranked_cte(group)
    <<~SQL
      WITH #{members_cte(group)},
      match_scores AS (
        SELECT p.user_id,
               SUM(ps.total_points) AS match_points,
               COUNT(*) FILTER (WHERE ps.breakdown->>'result_rule' = 'exact_score') AS exact_count
        FROM prediction_scores ps
        JOIN predictions p ON p.id = ps.prediction_id
        JOIN members me ON me.user_id = p.user_id
        GROUP BY p.user_id
      ),
      tournament_scores AS (
        SELECT tp.user_id, SUM(tps.total_points) AS tournament_points
        FROM tournament_prediction_scores tps
        JOIN tournament_predictions tp ON tp.id = tps.tournament_prediction_id
        JOIN members me ON me.user_id = tp.user_id
        GROUP BY tp.user_id
      ),
      ranked AS (
        SELECT m.user_id, m.username, m.avatar_url,
               COALESCE(ms.match_points, 0) + COALESCE(ts.tournament_points, 0) AS points,
               COALESCE(ms.exact_count, 0) AS exact_count,
               RANK() OVER (
                 ORDER BY COALESCE(ms.match_points, 0) + COALESCE(ts.tournament_points, 0) DESC,
                          COALESCE(ms.exact_count, 0) DESC
               ) AS rank_position,
               ROW_NUMBER() OVER (
                 ORDER BY COALESCE(ms.match_points, 0) + COALESCE(ts.tournament_points, 0) DESC,
                          COALESCE(ms.exact_count, 0) DESC,
                          m.user_id ASC
               ) AS row_number
        FROM members m
        LEFT JOIN match_scores ms ON ms.user_id = m.user_id
        LEFT JOIN tournament_scores ts ON ts.user_id = m.user_id
      )
    SQL
  end

  # The universe of ranked users: a group's members, or every user.
  def members_cte(group)
    if group
      <<~SQL
        members AS (
          SELECT u.id AS user_id, u.username, u.avatar_url
          FROM users u
          JOIN group_memberships gm ON gm.user_id = u.id
          WHERE gm.group_id = :group_id
        )
      SQL
    else
      <<~SQL
        members AS (
          SELECT u.id AS user_id, u.username, u.avatar_url
          FROM users u
        )
      SQL
    end
  end
end
