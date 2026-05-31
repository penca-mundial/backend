# frozen_string_literal: true

# A single team's row in a group-stage standings table, mirrored from
# football-data.org. We store the upstream `position` verbatim and never compute
# tiebreakers ourselves — different competitions use different tiebreaker rules,
# and the upstream is the source of truth. One row per team per tournament.
class Standing < ApplicationRecord
  belongs_to :tournament
  belongs_to :team

  validates :group, presence: true
  validates :position, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :played_games, :won, :draw, :lost, :goals_for, :goals_against, :points,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :goal_difference, numericality: { only_integer: true }
  validates :team_id, uniqueness: { scope: :tournament_id }

  # Group-then-position ordering for display (and for the grouped serializer,
  # which relies on rows arriving already ordered within each group).
  scope :ordered, -> { order(:group, :position) }
end
