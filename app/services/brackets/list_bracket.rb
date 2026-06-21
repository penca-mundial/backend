# frozen_string_literal: true

module Brackets
  # The knockout bracket payload for a tournament: every EXISTING knockout match
  # (no empty skeleton — create-on-resolve, ADR-0001), serialized with the
  # MatchBlueprint :bracket view (topology fields included), ordered by round then
  # bracket_position so the SPA can draw the tree.
  #
  # my_prediction (PredictionBlueprint — carries predicted_advancing_team_id, the
  # advance signal) is embedded for the viewer, but HARD-GATED to LOCKED picks:
  # an open future knockout match must never leak the viewer's advancing-team pick
  # to a rival reading the bracket. The gate (Prediction#locked?) is applied here,
  # before serialization — a non-locked pick never reaches the payload. Anonymous
  # viewer -> my_prediction always null.
  #
  # N+1-free: matches preload their teams; the viewer's predictions (with their
  # match and prediction_scores) load once.
  #
  # Returns a ServiceResult with { matches: [<hash>, ...] }.
  class ListBracket < Service
    KO_PHASES = (Match::PHASES - %w[group_stage]).freeze

    def initialize(tournament:, viewer: nil)
      @tournament = tournament
      @viewer = viewer
    end

    def call
      success(matches: ko_matches.map { |match| entry(match) })
    end

    private

    def entry(match)
      MatchBlueprint.render_as_hash(match, view: :bracket).merge(my_prediction: my_prediction(match))
    end

    def my_prediction(match)
      prediction = locked_predictions_by_match[match.id]
      prediction && PredictionBlueprint.render_as_hash(prediction)
    end

    # Existing knockout matches, round then bracket_position (unanchored last).
    def ko_matches
      @ko_matches ||= @tournament.matches.where(phase: KO_PHASES)
                                 .includes(:home_team, :away_team)
                                 .sort_by { |match| [ Match::PHASES.index(match.phase), match.bracket_position || Float::INFINITY ] }
    end

    def locked_predictions_by_match
      @locked_predictions_by_match ||= compute_locked_predictions
    end

    # The viewer's picks for these matches, gated to locked ones only (the hard
    # server-side fairness gate). select(&:locked?) reuses the same predicate as
    # the rest of the app; :match is preloaded so the predicate is N+1-free.
    def compute_locked_predictions
      return {} unless @viewer

      @viewer.predictions
             .where(match_id: ko_matches.map(&:id))
             .includes(:match, :prediction_scores)
             .select(&:locked?)
             .index_by(&:match_id)
    end
  end
end
