# frozen_string_literal: true

# JSON projection of a user's match prediction. `locked` is derived from the
# match state so the SPA can disable editing without a second round-trip.
class PredictionBlueprint < Blueprinter::Base
  identifier :id

  fields :match_id, :predicted_home_score, :predicted_away_score,
         :predicted_advancing_team_id, :locked_at

  field :locked, &:locked?
end
