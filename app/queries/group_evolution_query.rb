# frozen_string_literal: true

# Multi-line points/rank evolution for one group, for the per-penca stats chart.
#
# Lines (at most 5): the group's top 4 by the live leaderboard plus the current
# user — if the user is already in the top 4, the 5th member is added instead; a
# group with fewer than 5 members yields every member.
#
# Per line, the series is one point per snapshot date:
#   points -> straight from that date's GLOBAL snapshot row (group-independent).
#   rank   -> the user's position among the GROUP's members in that snapshot,
#             re-derived here with the SAME tiebreaks as the live leaderboard
#             (points desc, exact_count desc; ties share a rank). This is
#             Option A (SCRUM-153): no per-group snapshot rows exist, so the
#             group rank is computed from the global rows filtered to members.
#
# Gate (AC3): the chart is unavailable until the tournament has at least
# MIN_FINISHED_MATCHES finished matches. That threshold lives here, in one place.
#
# Reuses ranking_snapshots (global + for_tournament scopes, like
# UserEvolutionQuery) and LeaderboardQuery for the line-set. One leaderboard read
# (cached) + one snapshot read — no N+1, nothing hardcoded to a tournament size.
class GroupEvolutionQuery < ApplicationQuery
  MIN_FINISHED_MATCHES = 5
  MAX_LINES = 5

  Result = Struct.new(:available, :lines, keyword_init: true)
  Line = Struct.new(:user_id, :username, :avatar_url, :series, keyword_init: true)

  def initialize(group:, tournament:, user:, relation: nil)
    super(relation)
    @group = group
    @tournament = tournament
    @user = user
  end

  def call
    return Result.new(available: false, lines: []) unless gate_open?

    Result.new(available: true, lines: build_lines)
  end

  private

  # AC3: the single source of truth for the "5th match" rule.
  def gate_open?
    @tournament.matches.finished.count >= MIN_FINISHED_MATCHES
  end

  def build_lines
    # Load the snapshot matrix once, over EVERY member (the rank must consider
    # the whole group, not only the charted lines).
    rows_by_date = snapshot_rows(leaderboard_entries.map(&:user_id)).group_by { |row| row[:date] }
    ranks_by_date = rows_by_date.transform_values { |day_rows| rank_within(day_rows) }
    points_by_date = rows_by_date.transform_values { |day_rows| points_by_user(day_rows) }

    line_entries.map do |entry|
      Line.new(
        user_id:    entry.user_id,
        username:   entry.username,
        avatar_url: entry.avatar_url,
        series:     series_for(entry.user_id, ranks_by_date, points_by_date)
      )
    end
  end

  # The current group leaderboard (cached inside LeaderboardQuery). limit: nil so
  # the full membership is available to both pick the lines and rank by date.
  def leaderboard_entries
    @leaderboard_entries ||= LeaderboardQuery.new.call(tournament: @tournament, group: @group, limit: nil)
  end

  # Top 4 plus the current user: if the user is already in the top 4, take the
  # 5th entry too; otherwise append the user's own entry. Capped at MAX_LINES,
  # de-duplicated, order preserved (top of the table first).
  def line_entries
    entries = leaderboard_entries
    top = entries.first(MAX_LINES - 1)
    extra =
      if top.any? { |e| e.user_id == @user.id }
        entries[MAX_LINES - 1] # the 5th member
      else
        entries.find { |e| e.user_id == @user.id } # the user's own line
      end

    (top + [ extra ]).compact.uniq(&:user_id).first(MAX_LINES)
  end

  # Every member's global snapshot row for this tournament, as compact hashes
  # keyed by the snapshot's UTC date. Single read; member-scoped.
  def snapshot_rows(member_ids)
    (relation || RankingSnapshot.all)
      .global
      .for_tournament(@tournament)
      .where(user_id: member_ids)
      .pluck(:user_id, :snapshot_at, :points, :exact_count)
      .map do |user_id, snapshot_at, points, exact_count|
        { user_id:, date: snapshot_at.to_date, points:, exact_count: }
      end
  end

  # { user_id => points } for one day's rows.
  def points_by_user(day_rows)
    day_rows.to_h { |row| [ row[:user_id], row[:points] ] }
  end

  # Standard competition ranking (1,1,3) by points desc then exact_count desc —
  # the live leaderboard's tiebreaks. Returns { user_id => rank }.
  def rank_within(day_rows)
    sorted = day_rows.sort_by { |row| [ -row[:points], -row[:exact_count] ] }
    ranks = {}
    sorted.each_with_index do |row, index|
      previous = sorted[index - 1]
      ranks[row[:user_id]] =
        if index.positive? && tie?(previous, row)
          ranks[previous[:user_id]]
        else
          index + 1
        end
    end
    ranks
  end

  def tie?(a, b)
    a[:points] == b[:points] && a[:exact_count] == b[:exact_count]
  end

  # The user's chronological series: one { date, points, rank } per snapshot in
  # which they appear, ordered by date.
  def series_for(user_id, ranks_by_date, points_by_date)
    ranks_by_date.keys.sort.filter_map do |date|
      rank = ranks_by_date[date][user_id]
      next unless rank

      { date: date.iso8601, points: points_by_date[date][user_id], rank: rank }
    end
  end
end
