# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/tournament_predictions/me — the user's tournament prediction (or null).
    # PUT /api/v1/tournament_predictions    — create or update it (upsert).
    class TournamentPredictionsController < BaseController
      def show
        prediction = current_user.tournament_predictions.find_by(tournament: tournament)
        render json: prediction && TournamentPredictionBlueprint.render_as_hash(prediction)
      end

      def upsert
        result = ::TournamentPredictions::UpsertTournamentPrediction.call(
          user:            current_user,
          tournament:      tournament,
          champion_id:     prediction_params[:champion_id],
          runner_up_id:    prediction_params[:runner_up_id],
          third_place_id:  prediction_params[:third_place_id],
          fourth_place_id: prediction_params[:fourth_place_id],
          top_scorer_id:   prediction_params[:top_scorer_id]
        )

        if result.success?
          render json: TournamentPredictionBlueprint.render_as_hash(result.data)
        else
          render_error(
            code:    "validation_error",
            message: result.errors.to_sentence,
            status:  :unprocessable_content,
            details: { errors: result.errors }
          )
        end
      end

      private

      # The platform runs a single tournament (the World Cup); every prediction
      # hangs off it.
      def tournament
        @tournament ||= Tournament.first!
      end

      def prediction_params
        params.permit(:champion_id, :runner_up_id, :third_place_id, :fourth_place_id, :top_scorer_id)
      end
    end
  end
end
