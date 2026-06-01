# frozen_string_literal: true

# Public player projection. Embeds a compact team (TeamBlueprint :default) so the
# SPA can render a player row without a second request. Callers must preload
# :team to avoid N+1.
class PlayerBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :external_id, :team_id

  association :team, blueprint: TeamBlueprint, view: :default
end
