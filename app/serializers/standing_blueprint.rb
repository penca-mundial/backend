# frozen_string_literal: true

# Public standings projection. Embeds a compact team object (same shape as
# MatchBlueprint) so the SPA can render a standings row without a second
# request. Callers must preload :team to avoid N+1.
class StandingBlueprint < Blueprinter::Base
  identifier :id

  fields :group, :position, :played_games, :won, :draw, :lost,
         :goals_for, :goals_against, :goal_difference, :points, :form

  field(:team) { |standing| StandingBlueprint.team_hash(standing.team) }

  def self.team_hash(team)
    return nil if team.nil?

    { id: team.id, name: team.name, code3: team.code3, flag_url: team.flag_url }
  end

  # Group an already-ordered (group, position) collection into
  # { "A" => [row, row, ...], "B" => [...] }, preserving order both across groups
  # and within each group. Keeps the grouping out of the controller.
  def self.grouped(standings)
    render_as_hash(standings).group_by { |row| row[:group] }
  end
end
