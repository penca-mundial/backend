# frozen_string_literal: true

module Profiles
  # Assembles the public profile payload for a target user, as seen by any
  # authenticated viewer:
  #
  #   user             — id / username / avatar_url
  #   global_ranking   — the target's row in the global leaderboard (+ universe size)
  #   shared_groups    — the target's standing in the pencas viewer and target
  #                      SHARE (the general pool always; plus private groups both
  #                      belong to). Non-shared groups are never exposed.
  #   tournament_prediction — the target's podium/scorer pick, gated by
  #                      Tournament#predictions_locked? (available/reason pattern).
  #   stats            — accuracy buckets over the target's scored predictions.
  #
  # No match-by-match picks here — those live behind the paginated
  # /users/:id/predictions feed, with their own server-side lock gate.
  class BuildProfile < Service
    def initialize(viewer:, target:, tournament:)
      @viewer = viewer
      @target = target
      @tournament = tournament
    end

    def call
      success(
        user:                  user_hash,
        global_ranking:        global_ranking,
        shared_groups:         shared_groups,
        tournament_prediction: tournament_prediction,
        stats:                 ProfileStatsQuery.call(user: @target, tournament: @tournament)
      )
    end

    private

    def user_hash
      { id: @target.id, username: @target.username, avatar_url: @target.avatar_url }
    end

    def global_ranking
      row = target_row(group: nil)
      {
        rank_position: row&.rank_position,
        points:        row&.points || 0,
        exact_count:   row&.exact_count || 0,
        total:         User.where(system: false).count
      }
    end

    def shared_groups
      shared_group_scope.map do |group|
        row = target_row(group: group)
        {
          group:         { id: group.id, name: group.name, is_general_pool: group.is_general_pool? },
          rank_position: row&.rank_position,
          points:        row&.points || 0,
          total:         group.memberships.count
        }
      end
    end

    # The target's own row inside the leaderboard window (it sits at the centre of
    # the neighbour window position_of returns).
    def target_row(group:)
      leaderboard.position_of(@target, tournament: @tournament, group: group)
                 .find { |row| row.user_id == @target.id }
    end

    # Groups viewer and target share: the intersection of their memberships, plus
    # the general pool whenever the target belongs to it (it is shared by
    # construction — everyone is enrolled). General pool first, then by name.
    def shared_group_scope
      ids = @viewer.group_ids & @target.group_ids
      ids |= [ general_pool_id ] if general_pool_id && @target.group_ids.include?(general_pool_id)

      Group.where(id: ids).sort_by { |group| [ group.is_general_pool? ? 0 : 1, group.name ] }
    end

    def general_pool_id
      return @general_pool_id if defined?(@general_pool_id)

      @general_pool_id = Group.where(is_general_pool: true).pick(:id)
    end

    # Specials reveal: hidden until the tournament starts (first kickoff), then
    # the target's pick (or null if they made none).
    def tournament_prediction
      return { available: false, reason: "tournament_not_started" } unless @tournament.predictions_locked?

      prediction = @target.tournament_predictions
                          .includes(:champion, :runner_up, :third_place, :fourth_place, top_scorer: :team)
                          .find_by(tournament: @tournament)

      { available: true, prediction: prediction && TournamentPredictionBlueprint.render_as_hash(prediction) }
    end

    def leaderboard
      @leaderboard ||= LeaderboardQuery.new
    end
  end
end
