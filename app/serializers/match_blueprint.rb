# frozen_string_literal: true

# Public fixture projection. Embeds a compact home/away team object so the SPA
# can render a match card without a second request. Callers must preload
# :home_team and :away_team to avoid N+1.
class MatchBlueprint < Blueprinter::Base
  identifier :id

  fields :external_id, :tournament_id, :kickoff_at, :status, :phase, :group,
         :minute, :home_score, :away_score, :advancing_team_id

  association :home_team, blueprint: TeamBlueprint, view: :default
  association :away_team, blueprint: TeamBlueprint, view: :default
end
