# frozen_string_literal: true

class PhaseMultiplier < ApplicationRecord
  # The phases mirror Match's phase enum.
  PHASES = Match::PHASES

  enum :phase, PHASES.index_with(&:itself)

  has_paper_trail

  validates :phase, presence: true, uniqueness: true
  validates :multiplier, numericality: { greater_than: 0 }

  # Multiplier for the given phase as a Float, or nil when unconfigured.
  def self.for(phase)
    find_by(phase: phase)&.multiplier&.to_f
  end
end
