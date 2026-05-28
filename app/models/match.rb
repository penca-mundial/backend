# frozen_string_literal: true

class Match < ApplicationRecord
  STATUSES = %w[scheduled live finished postponed cancelled].freeze
  PHASES = %w[
    group_stage round_of_32 round_of_16 quarter_final semi_final third_place final
  ].freeze
  # Which slot of the next-round match the winner of this one fills. Defined
  # here because the values double as DB enum integers and as enum keys below.
  FEEDS_INTO_SLOTS = { home: 0, away: 1 }.freeze

  has_paper_trail

  belongs_to :tournament
  belongs_to :home_team, class_name: "Team"
  belongs_to :away_team, class_name: "Team"
  belongs_to :advancing_team, class_name: "Team", optional: true

  # Self-referential bracket progression: this match's winner advances to
  # `feeds_into`; reciprocally, `fed_by` exposes the matches that feed into
  # this one. Propagating the winning team itself lives in
  # Matches::PropagateWinner (task-073c), not here.
  belongs_to :feeds_into,
             class_name: "Match", foreign_key: :feeds_into_match_id,
             optional: true, inverse_of: :fed_by
  has_many :fed_by,
           class_name: "Match", foreign_key: :feeds_into_match_id,
           dependent: :nullify, inverse_of: :feeds_into

  # prefix: true avoids clashes between status/phase predicates and other methods.
  enum :status, STATUSES.index_with(&:itself), prefix: true
  enum :phase,  PHASES.index_with(&:itself),   prefix: true
  enum :feeds_into_slot, FEEDS_INTO_SLOTS, prefix: :feeds_into

  validates :external_id, presence: true, uniqueness: true
  validates :kickoff_at, presence: true
  validates :phase, presence: true
  validates :home_score, :away_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :advancing_team_is_a_participant
  validate :advancing_team_not_in_group_stage
  validate :final_does_not_feed_into
  validate :feeds_into_slot_required_with_feeds_into

  # original_kickoff_at records the first scheduled time and is immutable once set.
  before_validation :set_original_kickoff_at, on: :create

  scope :live,      -> { status_live }
  scope :scheduled, -> { status_scheduled }
  scope :finished,  -> { status_finished }

  private

  def set_original_kickoff_at
    self.original_kickoff_at = kickoff_at
  end

  def advancing_team_is_a_participant
    return if advancing_team_id.blank?
    return if [ home_team_id, away_team_id ].include?(advancing_team_id)

    errors.add(:advancing_team_id, :not_a_participant)
  end

  def advancing_team_not_in_group_stage
    return if advancing_team_id.blank?
    return unless phase_group_stage?

    errors.add(:advancing_team_id, :not_in_group_stage)
  end

  def final_does_not_feed_into
    return if feeds_into_match_id.blank?
    return unless phase_final?

    errors.add(:feeds_into_match_id, :not_allowed_for_final)
  end

  def feeds_into_slot_required_with_feeds_into
    return if feeds_into_match_id.blank?
    return if feeds_into_slot.present?

    errors.add(:feeds_into_slot, :blank)
  end
end
