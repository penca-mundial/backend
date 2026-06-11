# frozen_string_literal: true

# The user's rank within each of the given groups, as a {group_id => rank}
# hash, using the SAME ranking definition as the rankings API (it delegates to
# LeaderboardQuery#position_of, the exact source /rankings/groups/:id uses), so
# Home and the leaderboard never disagree. A group where the user has no ranked
# row maps to nil; nil tournament (none exists yet) yields an empty hash.
#
# One targeted position_of lookup per group. /groups/me lists only the user's
# own groups (bounded by Group::MAX_OWNED_GROUPS plus joined pencas), so this is
# a small, bounded number of reads rather than an unbounded N+1, and — like
# position_of itself — it is intentionally not cached.
class GroupRanksQuery < ApplicationQuery
  def initialize(user:, tournament:, groups:, leaderboard: LeaderboardQuery.new)
    super(nil)
    @user = user
    @tournament = tournament
    @groups = groups
    @leaderboard = leaderboard
  end

  def call
    return {} if tournament.nil?

    groups.each_with_object({}) do |group, ranks|
      ranks[group.id] = rank_within(group)
    end
  end

  private

  attr_reader :user, :tournament, :groups, :leaderboard

  def rank_within(group)
    row = leaderboard
          .position_of(user, tournament: tournament, group: group)
          .find { |entry| entry.user_id == user.id }
    row&.rank_position
  end
end
