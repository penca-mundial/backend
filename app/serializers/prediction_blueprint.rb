# frozen_string_literal: true

# JSON projection of a user's match prediction. `locked` is derived from the
# match state so the SPA can disable editing without a second round-trip.
class PredictionBlueprint < Blueprinter::Base
  identifier :id

  fields :match_id, :predicted_home_score, :predicted_away_score,
         :predicted_advancing_team_id, :locked_at

  field :locked, &:locked?

  # Points earned once the match is scored (Phase 5 / SCRUM-137). Sourced from
  # the prediction's PredictionScore (one row per prediction, the canonical
  # scoring store — not a column here), defaulting to 0 until a score exists.
  field(:points_earned) { |prediction| prediction.prediction_scores.first&.total_points || 0 }
end
