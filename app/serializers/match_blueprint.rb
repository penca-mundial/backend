# frozen_string_literal: true

# Public fixture projection. Embeds a compact home/away team object so the SPA
# can render a match card without a second request. Callers must preload
# :home_team and :away_team to avoid N+1.
class MatchBlueprint < Blueprinter::Base
  identifier :id

  fields :external_id, :tournament_id, :kickoff_at, :status, :phase, :group,
         :home_score, :away_score, :advancing_team_id

  field(:home_team) { |match| MatchBlueprint.team_hash(match.home_team) }
  field(:away_team) { |match| MatchBlueprint.team_hash(match.away_team) }

  def self.team_hash(team)
    return nil if team.nil?

    { id: team.id, name: team.name, code3: team.code3, flag_url: team.flag_url }
  end
end
