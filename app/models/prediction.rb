# frozen_string_literal: true

class Prediction < ApplicationRecord
  LOCK_THRESHOLD = 1.minute

  has_paper_trail

  belongs_to :user
  belongs_to :match
  belongs_to :predicted_advancing_team, class_name: "Team", optional: true

  # At most one score per prediction (enforced by a unique index on
  # prediction_id), but modelled as has_many so User#prediction_scores can
  # reach them through :predictions without a source override. The FK has no
  # ON DELETE cascade, so dependent: :destroy clears scores with the prediction.
  has_many :prediction_scores, dependent: :destroy

  validates :predicted_home_score, :predicted_away_score,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 20 }
  validate :advancing_team_required_for_knockout
  validate :advancing_team_is_a_participant

  # A prediction is locked once the match is flagged locked, has left the
  # scheduled state, or is about to kick off.
  def locked?
    return true if locked_at.present?
    return true unless match.status_scheduled?

    match.kickoff_at <= LOCK_THRESHOLD.from_now
  end

  private

  def advancing_team_required_for_knockout
    return if match.nil? || match.phase_group_stage?
    return if predicted_advancing_team_id.present?

    errors.add(:predicted_advancing_team_id, :required)
  end

  def advancing_team_is_a_participant
    return if predicted_advancing_team_id.blank? || match.nil?
    return if [ match.home_team_id, match.away_team_id ].include?(predicted_advancing_team_id)

    errors.add(:predicted_advancing_team_id, :not_a_participant)
  end
end
