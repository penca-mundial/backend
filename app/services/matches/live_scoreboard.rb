# frozen_string_literal: true

module Matches
  # Builds the GET /matches/live payload for a signed-in user: each live match
  # (already team-preloaded) serialized with MatchBlueprint, enriched with the
  # user's own prediction and the points it WOULD earn if the match ended at its
  # current live score (projected_points). Both are null when the user has no
  # prediction for that match.
  #
  # No N+1: the user's predictions for the listed matches are loaded once (with
  # their scores, which PredictionBlueprint reads), and the scoring-config
  # lookups are memoized across every match via shared caches — so the work is
  # constant in the number of live matches, not one query per match.
  #
  # Returns a ServiceResult with { entries: [<hash>, ...] }.
  class LiveScoreboard < Service
    def initialize(matches:, user:)
      @matches = matches.to_a
      @user = user
      @points_cache = {}
      @multiplier_cache = {}
    end

    def call
      success(entries: @matches.map { |match| entry(match) })
    end

    private

    def entry(match)
      prediction = predictions_by_match[match.id]

      MatchBlueprint.render_as_hash(match).merge(
        my_prediction:    prediction && PredictionBlueprint.render_as_hash(prediction),
        projected_points: prediction && calculator_for(match).total_for(prediction)
      )
    end

    # The user's predictions for the listed matches, keyed by match_id. Scores
    # are preloaded because PredictionBlueprint#points_earned reads them.
    def predictions_by_match
      @predictions_by_match ||=
        @user.predictions
             .includes(:prediction_scores)
             .where(match_id: @matches.map(&:id))
             .index_by(&:match_id)
    end

    # Per-match calculator sharing the config caches, so a rule/multiplier is
    # looked up at most once across the whole scoreboard.
    def calculator_for(match)
      Scoring::MatchScoreCalculator.new(
        match: match, points_cache: @points_cache, multiplier_cache: @multiplier_cache
      )
    end
  end
end
