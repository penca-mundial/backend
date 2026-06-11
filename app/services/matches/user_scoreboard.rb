# frozen_string_literal: true

module Matches
  # Builds a per-user match payload for a signed-in user: each match (already
  # team-preloaded) serialized with MatchBlueprint, enriched with the user's own
  # prediction and the points it scores AT THAT MATCH'S CURRENT SCORE — computed
  # on the fly, never read from stored PredictionScore rows. The same shape backs
  # both /matches/live (current live score) and /matches/recent_finished (final
  # score): in each case the calculator reads whatever score the match carries.
  #
  #   my_prediction: { predicted_home_score, predicted_away_score, points }  (or null)
  #
  # The points are per-match (this match only), never accumulated.
  #
  # No N+1: the user's predictions for the listed matches are loaded once, and
  # the scoring-config lookups are memoized across every match via shared caches,
  # so the work is constant in the number of matches.
  #
  # Returns a ServiceResult with { entries: [<hash>, ...] }.
  class UserScoreboard < Service
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
      MatchBlueprint.render_as_hash(match).merge(my_prediction: my_prediction(match))
    end

    # The compact prediction projection: the picked score plus the points it
    # earns against the match's current score (the calculator recomputes from the
    # rules — it does not read a saved PredictionScore). null when the user has no
    # prediction for this match.
    def my_prediction(match)
      prediction = predictions_by_match[match.id]
      return nil unless prediction

      {
        predicted_home_score: prediction.predicted_home_score,
        predicted_away_score: prediction.predicted_away_score,
        points:               calculator_for(match).total_for(prediction)
      }
    end

    # The user's predictions for the listed matches, keyed by match_id (one query).
    def predictions_by_match
      @predictions_by_match ||=
        @user.predictions.where(match_id: @matches.map(&:id)).index_by(&:match_id)
    end

    # Per-match calculator sharing the config caches, so a rule/multiplier is
    # looked up at most once across the whole payload.
    def calculator_for(match)
      Scoring::MatchScoreCalculator.new(
        match: match, points_cache: @points_cache, multiplier_cache: @multiplier_cache
      )
    end
  end
end
