# frozen_string_literal: true

module Api
  module V1
    # GET    /api/v1/predictions/me   — the current user's predictions (paginated, ?match_id=).
    # PUT    /api/v1/predictions      — create or update a prediction (upsert).
    # DELETE /api/v1/predictions/:id  — delete an own, still-open prediction.
    class PredictionsController < BaseController
      def index
        render_paginated(scoped_predictions, PredictionBlueprint)
      end

      def upsert
        result = ::Predictions::UpsertPrediction.call(
          user:                        current_user,
          match:                       Match.find(prediction_params[:match_id]),
          predicted_home_score:        integer_or_nil(prediction_params[:predicted_home_score]),
          predicted_away_score:        integer_or_nil(prediction_params[:predicted_away_score]),
          predicted_advancing_team_id: integer_or_nil(prediction_params[:predicted_advancing_team_id])
        )

        if result.success?
          render json: PredictionBlueprint.render(result.data), content_type: "application/json"
        else
          render_validation_error(result.errors)
        end
      end

      def destroy
        prediction = Prediction.find(params[:id])
        return render_forbidden unless prediction.user_id == current_user.id

        result = ::Predictions::DeletePrediction.call(prediction: prediction)
        return render_validation_error(result.errors) if result.failure?

        head :no_content
      end

      private

      def scoped_predictions
        scope = current_user.predictions.includes(:match, :prediction_scores)
        scope = scope.where(match_id: params[:match_id]) if params[:match_id].present?
        scope
      end

      def prediction_params
        params.permit(:match_id, :predicted_home_score, :predicted_away_score, :predicted_advancing_team_id)
      end

      def integer_or_nil(value)
        Integer(value, exception: false)
      end

      def render_validation_error(errors)
        render_error(
          code:    "validation_error",
          message: errors.to_sentence,
          status:  :unprocessable_content,
          details: { errors: errors }
        )
      end

      def render_forbidden
        render_error(
          code:    "forbidden",
          message: I18n.t("errors.not_owner", default: "No podés modificar pronósticos de otra persona."),
          status:  :forbidden
        )
      end
    end
  end
end
