# frozen_string_literal: true

# Ranked leaderboard for a group (or, with group: nil, every user — the global
# path used by the rankings API and by Rankings::CaptureSnapshot).
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
# window: :total (default) ranks the cumulative numbers above — the pre-window
# behaviour, untouched. :today / :week rank by the DELTA gained inside the
# window: current cumulative minus the user's row in the ANCHOR snapshot — the
# most recent GLOBAL (group_id NULL) snapshot strictly before the window start.
# No anchor (first days) -> baseline 0, so the delta degrades to the cumulative
# total. A group window derives from the SAME global anchor filtered to the
# group's members (Option A: per-group snapshot rows do not exist); the delta is
# computed and ranked in SQL, never by merging rows in Ruby (the global pool is
# ~100k users). Window starts are midnight UTC by construction, independent of
# Time.zone (cf. RankingSnapshotJob).
#
# Tiebreakers: (window) points, then (window) exact_count. A third "sum of goal
# differences" tiebreaker is intentionally NOT implemented — there is no clean
# stored source for it (the breakdown carries only the rule symbols, not the
# predicted/real margins), so remaining ties share a rank (SCRUM-149).
#
# Raw SQL: the window function over a multi-source LEFT-JOIN aggregation is
# clearer as SQL than as an AR chain. Results are cached briefly (shorter while a
# match is live); a cache hit does not touch the database.
class LeaderboardQuery < ApplicationQuery
  LIVE_TTL = 30.seconds
  IDLE_TTL = 5.minutes
  DEFAULT_LIMIT = 100
  NEIGHBORS = 2 # rows shown above/below the user in #position_of

  # window name => days back from today's UTC midnight to the window start.
  WINDOWS = { total: nil, today: 0, week: 7 }.freeze

  Row = Struct.new(
    :user_id, :username, :avatar_url, :points, :exact_count, :rank_position,
    keyword_init: true
  )

  # The ranked rows (cached). tournament is REQUIRED — points and exact_count are
  # scoped to it. group: nil ranks every user (global), otherwise the group's
  # members. The cache key includes tournament.id and window so two tournaments
  # (or two windows) never share an entry.
  def call(tournament:, group: nil, limit: DEFAULT_LIMIT, window: :total)
    validate_window!(window)
    key = [ "leaderboard", tournament.id, group&.id, limit, window ]
    cached = Rails.cache.read(key)
    return cached if cached

    rows = run(leaderboard_sql(group, window), binds(tournament, group, window, limit: limit))
    Rails.cache.write(key, rows, expires_in: ttl)
    rows
  end

  # The user's row plus up to NEIGHBORS rows above and below it (a small context
  # window), scoped to the tournament and ranked within the same window as the
  # list. Empty when the user is outside the universe (e.g. not a member). Not
  # cached — a targeted lookup, not the hot list.
  def position_of(user, tournament:, group: nil, window: :total)
    validate_window!(window)
    run(window_sql(group, window), binds(tournament, group, window, user_id: user.id))
  end

  private

  def validate_window!(window)
    raise ArgumentError, "unknown window: #{window.inspect}" unless WINDOWS.key?(window)
  end

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

  # Named binds; tournament_id always (the scope), group_id only when scoping to
  # a group, window_start only when ranking a delta window.
  def binds(tournament, group, window, **extra)
    base = { tournament_id: tournament.id }
    base[:group_id] = group.id if group
    base[:window_start] = window_start(window) unless window == :total
    base.merge(extra)
  end

  # Midnight UTC of (today - days back), built from the date so it cannot shift
  # with Time.zone / the host zone.
  def window_start(window)
    (Time.current.utc.to_date - WINDOWS.fetch(window)).to_time(:utc)
  end

  # Reuse the existing "is anything live?" signal (cf. MatchesController).
  def ttl
    Match.status_live.exists? ? LIVE_TTL : IDLE_TTL
  end

  def leaderboard_sql(group, window)
    <<~SQL.squish
      #{ranked_cte(group, window)}
      SELECT user_id, username, avatar_url, points, exact_count, rank_position
      FROM ranked
      ORDER BY row_number
      LIMIT :limit
    SQL
  end

  def window_sql(group, window)
    <<~SQL.squish
      #{ranked_cte(group, window)},
      target AS (SELECT row_number AS rn FROM ranked WHERE user_id = :user_id)
      SELECT r.user_id, r.username, r.avatar_url, r.points, r.exact_count, r.rank_position
      FROM ranked r
      JOIN target t ON r.row_number BETWEEN t.rn - #{NEIGHBORS} AND t.rn + #{NEIGHBORS}
      ORDER BY r.row_number
    SQL
  end

  # The shared CTE: the member universe LEFT JOINed to the two score sources
  # (and, for delta windows, to the anchor snapshot), with RANK() for display
  # (shared ties) and ROW_NUMBER() for stable ordering and the position_of
  # window.
  def ranked_cte(group, window)
    <<~SQL
      WITH #{members_cte(group)},
      match_scores AS (
        SELECT p.user_id,
               SUM(ps.total_points) AS match_points,
               COUNT(*) FILTER (WHERE ps.breakdown->>'result_rule' = 'exact_score') AS exact_count
        FROM prediction_scores ps
        JOIN predictions p ON p.id = ps.prediction_id
        JOIN matches mt ON mt.id = p.match_id AND mt.tournament_id = :tournament_id
        JOIN members me ON me.user_id = p.user_id
        GROUP BY p.user_id
      ),
      tournament_scores AS (
        SELECT tp.user_id, SUM(tps.total_points) AS tournament_points
        FROM tournament_prediction_scores tps
        JOIN tournament_predictions tp ON tp.id = tps.tournament_prediction_id
                                       AND tp.tournament_id = :tournament_id
        JOIN members me ON me.user_id = tp.user_id
        GROUP BY tp.user_id
      ),
      #{anchor_cte(window)}ranked AS (
        SELECT m.user_id, m.username, m.avatar_url,
               #{points_expr(window)} AS points,
               #{exact_expr(window)} AS exact_count,
               RANK() OVER (
                 ORDER BY #{points_expr(window)} DESC,
                          #{exact_expr(window)} DESC
               ) AS rank_position,
               ROW_NUMBER() OVER (
                 ORDER BY #{points_expr(window)} DESC,
                          #{exact_expr(window)} DESC,
                          m.user_id ASC
               ) AS row_number
        FROM members m
        LEFT JOIN match_scores ms ON ms.user_id = m.user_id
        LEFT JOIN tournament_scores ts ON ts.user_id = m.user_id#{anchor_join(window)}
      )
    SQL
  end

  # Cumulative points, minus the anchor baseline when ranking a delta window.
  def points_expr(window)
    base = "COALESCE(ms.match_points, 0) + COALESCE(ts.tournament_points, 0)"
    window == :total ? base : "#{base} - COALESCE(a.points, 0)"
  end

  def exact_expr(window)
    base = "COALESCE(ms.exact_count, 0)"
    window == :total ? base : "#{base} - COALESCE(a.exact_count, 0)"
  end

  # The per-user baseline for delta windows: the most recent GLOBAL snapshot
  # strictly before the window start, restricted to the member universe (this is
  # how a group window derives from the global rows — Option A). Empty when no
  # snapshot predates the window, in which case COALESCE(a.*, 0) makes the delta
  # equal the cumulative total.
  def anchor_cte(window)
    return "" if window == :total

    <<~SQL
      anchor AS (
        SELECT rs.user_id, rs.points, rs.exact_count
        FROM ranking_snapshots rs
        JOIN members me ON me.user_id = rs.user_id
        WHERE rs.tournament_id = :tournament_id
          AND rs.group_id IS NULL
          AND rs.snapshot_at = (
            SELECT MAX(prev.snapshot_at)
            FROM ranking_snapshots prev
            WHERE prev.tournament_id = :tournament_id
              AND prev.group_id IS NULL
              AND prev.snapshot_at < :window_start
          )
      ),
    SQL
  end

  def anchor_join(window)
    window == :total ? "" : "\nLEFT JOIN anchor a ON a.user_id = m.user_id"
  end

  # The universe of ranked users: a group's members, or every non-system user.
  # The global branch excludes service accounts (users.system, NOT NULL default
  # false; IS NOT TRUE stays correct even if the constraint ever relaxes) — the
  # system user exists only to own records and must not be ranked. The group
  # branch needs no filter: membership rules there, and the enrolment guard
  # keeps system accounts out of every group. Old GLOBAL snapshots may carry a
  # system row, but snapshots are only read as the delta ANCHOR (joined back to
  # this CTE) — entries always come from the live, filtered universe, so no
  # snapshot cleanup is needed.
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
          WHERE u.system IS NOT TRUE
        )
      SQL
    end
  end
end
