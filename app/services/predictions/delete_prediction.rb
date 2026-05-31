# frozen_string_literal: true

module Predictions
  # Deletes a prediction, but only while its match is still open. Ownership is an
  # authorization concern handled by the controller; this service owns the "can
  # it still be deleted?" business rule. Raises Penca::ServiceError once locked.
  class DeletePrediction < Service
    def initialize(prediction:)
      @prediction = prediction
    end

    def call
      raise_service_error("No podés borrar el pronóstico de un partido ya cerrado.") if @prediction.locked?

      @prediction.destroy!
      success(@prediction)
    end
  end
end
