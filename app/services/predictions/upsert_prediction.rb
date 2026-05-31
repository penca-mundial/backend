# frozen_string_literal: true

module Predictions
  # Creates or updates a user's prediction for a match, enforcing the business
  # rules up front with clear (Spanish) messages. The Prediction model validates
  # the same score/advancing-team invariants as a backstop; here we also gate on
  # the match being open (scheduled and more than LOCK_THRESHOLD before kickoff),
  # which is a service-level concern, not a model invariant.
  class UpsertPrediction < Service
    LOCK_THRESHOLD = 1.minute
    SCORE_RANGE = 0..20

    def initialize(user:, match:, predicted_home_score:, predicted_away_score:, predicted_advancing_team_id: nil)
      @user = user
      @match = match
      @predicted_home_score = predicted_home_score
      @predicted_away_score = predicted_away_score
      @predicted_advancing_team_id = predicted_advancing_team_id
    end

    def call
      ensure_match_open!
      ensure_scores_in_range!
      ensure_advancing_team_valid!

      prediction = Prediction.find_or_initialize_by(user: @user, match: @match)
      prediction.update!(
        predicted_home_score: @predicted_home_score,
        predicted_away_score: @predicted_away_score,
        predicted_advancing_team_id: @predicted_advancing_team_id
      )
      success(prediction)
    end

    private

    def ensure_match_open!
      raise_service_error("El partido no está disponible para pronosticar.") unless @match.status_scheduled?
      raise_service_error("El partido ya está cerrado para pronósticos.") if locked?
    end

    def locked?
      @match.kickoff_at <= Time.current + LOCK_THRESHOLD
    end

    def ensure_scores_in_range!
      return if score_valid?(@predicted_home_score) && score_valid?(@predicted_away_score)

      raise_service_error("Los goles deben ser un número entre 0 y 20.")
    end

    def ensure_advancing_team_valid!
      return if @match.phase_group_stage?

      if @predicted_advancing_team_id.blank?
        raise_service_error("Tenés que elegir el equipo que avanza.")
      elsif [ @match.home_team_id, @match.away_team_id ].exclude?(@predicted_advancing_team_id)
        raise_service_error("El equipo que avanza debe ser uno de los que juegan el partido.")
      end
    end

    def score_valid?(score)
      score.is_a?(Integer) && SCORE_RANGE.cover?(score)
    end
  end
end
