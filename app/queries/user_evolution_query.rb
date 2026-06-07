# frozen_string_literal: true

# A user's points/position over time, read from RankingSnapshot.
#
# Always intra-tournament: `tournament` is required (the caller — the rankings
# controller — resolves the current tournament and passes it; this stays a pure
# query and never reaches for CurrentTournamentQuery itself).
#
#   group: nil  -> global evolution  (snapshots with group_id NULL, via .global)
#   group: <g>  -> that group's evolution (via .for_group)
#
# `days` is a RELATIVE window: snapshots with snapshot_at >= Time.current - days.
# Relative (not calendar) on purpose, so there is no timezone-boundary edge.
#
# Returns an array of { snapshot_at:, points:, rank_position: } ordered by
# snapshot_at ASC. exact_count lives on the table but is intentionally left out
# of the shape (kept minimal to the AC).
class UserEvolutionQuery < ApplicationQuery
  DEFAULT_DAYS = 30

  def initialize(user:, tournament:, group: nil, days: DEFAULT_DAYS, relation: nil)
    super(relation)
    @user = user
    @tournament = tournament
    @group = group
    @days = days
  end

  def call
    base = (relation || RankingSnapshot.all)
      .where(user: @user)
      .for_tournament(@tournament)
      .where(snapshot_at: window_start..)

    scoped = @group ? base.for_group(@group) : base.global

    scoped.order(:snapshot_at)
          .pluck(:snapshot_at, :points, :rank_position)
          .map { |snapshot_at, points, rank_position| { snapshot_at:, points:, rank_position: } }
  end

  private

  def window_start
    Time.current - @days.days
  end
end
