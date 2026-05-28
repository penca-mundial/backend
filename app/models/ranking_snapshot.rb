# frozen_string_literal: true

class RankingSnapshot < ApplicationRecord
  belongs_to :user
  belongs_to :group, optional: true

  validates :points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :rank_position, numericality: { only_integer: true, greater_than: 0 }
  validates :snapshot_at, presence: true

  # Global leaderboard rows have no group; per-group rows reference one.
  scope :global,    -> { where(group_id: nil) }
  scope :for_group, ->(group) { where(group: group) }
end
