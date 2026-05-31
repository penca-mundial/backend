# frozen_string_literal: true

# JSON projection of a user's tournament-wide prediction (podium + top scorer).
# `locked` is derived from the tournament start so the SPA can disable editing.
class TournamentPredictionBlueprint < Blueprinter::Base
  identifier :id

  fields :tournament_id, :champion_id, :runner_up_id, :third_place_id,
         :fourth_place_id, :top_scorer_id, :locked_at

  field :locked, &:locked?
end
