# frozen_string_literal: true

class Tournament < ApplicationRecord
  belongs_to :champion,     class_name: "Team",   optional: true
  belongs_to :runner_up,    class_name: "Team",   optional: true
  belongs_to :third_place,  class_name: "Team",   optional: true
  belongs_to :fourth_place, class_name: "Team",   optional: true
  belongs_to :top_scorer,   class_name: "Player", optional: true

  has_many :teams
  has_many :matches
  has_many :standings
  has_many :players, through: :teams

  validates :name, :starts_at, :ends_at, presence: true

  # Tournaments currently in their playing window — the ones whose standings are
  # worth refreshing. Time-window based, with no competition-specific assumption.
  scope :active, -> { where(starts_at: ..Time.current).where(ends_at: Time.current..) }
end
