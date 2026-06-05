# frozen_string_literal: true

# Public projection for the CALCULATED group-stage tables (GroupStandingsQuery).
# One object per group: { name, standings: [ row, ... ] }, where each row embeds
# the compact team object (same shape as MatchBlueprint/StandingBlueprint) plus
# the computed line. Distinct from StandingBlueprint, which mirrors the upstream
# /standings feed.
class GroupStandingBlueprint < Blueprinter::Base
  # One team's computed line within a group table.
  class Row < Blueprinter::Base
    fields :played, :won, :drawn, :lost,
           :goals_for, :goals_against, :goal_difference, :points, :position

    association :team, blueprint: TeamBlueprint, view: :default
  end

  fields :name

  association :standings, blueprint: Row
end
