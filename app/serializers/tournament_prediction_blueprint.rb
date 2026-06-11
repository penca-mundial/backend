# frozen_string_literal: true

# JSON projection of a user's tournament-wide prediction (podium + top scorer).
# `locked` is derived from the tournament start so the SPA can disable editing.
# The podium teams and the top scorer are embedded (alongside the raw FK ids the
# editor still uses) so Home can render the picks without extra requests; callers
# must preload :champion, :runner_up, :third_place, :fourth_place and
# top_scorer => :team to keep it N+1-free.
class TournamentPredictionBlueprint < Blueprinter::Base
  identifier :id

  fields :tournament_id, :champion_id, :runner_up_id, :third_place_id,
         :fourth_place_id, :top_scorer_id, :locked_at

  field :locked, &:locked?

  association :champion,     blueprint: TeamBlueprint, view: :default
  association :runner_up,    blueprint: TeamBlueprint, view: :default
  association :third_place,  blueprint: TeamBlueprint, view: :default
  association :fourth_place, blueprint: TeamBlueprint, view: :default
  association :top_scorer,   blueprint: PlayerBlueprint
end
