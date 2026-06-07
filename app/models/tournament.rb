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
  has_many :tournament_predictions
  has_many :players, through: :teams

  validates :name, :starts_at, :ends_at, presence: true
  # One tournament per competition code; nil is allowed (and not unique-checked),
  # backed by a partial unique index (SCRUM-274).
  validates :external_code, uniqueness: true, allow_nil: true

  # Tournaments currently in their playing window — the ones whose standings are
  # worth refreshing. Time-window based, with no competition-specific assumption.
  scope :active, -> { where(starts_at: ..Time.current).where(ends_at: Time.current..) }

  # Tournament-prediction deadline: one minute before the first kickoff, derived
  # from the fixture rather than starts_at (computed-from-matches, cf. ADR 0002 —
  # starts_at is the calendar day, the opener kicks off hours later). nil while
  # the fixture has not been ingested. Memoized per instance (nil included).
  def predictions_lock_at
    return @predictions_lock_at if defined?(@predictions_lock_at)

    first_kickoff = matches.minimum(:kickoff_at)
    @predictions_lock_at = first_kickoff && first_kickoff - 1.minute
  end

  def predictions_locked?
    predictions_lock_at.present? && predictions_lock_at <= Time.current
  end

  # Teams actually playing: distinct non-nil home/away ids across the fixture.
  # Unresolved knockout matches carry nil team slots (ADR 0001) — compacted out.
  # The tournament tag alone does NOT make a team a participant (seed leftovers).
  def participating_team_ids
    @participating_team_ids ||= matches.pluck(:home_team_id, :away_team_id).flatten.compact.uniq
  end
end
