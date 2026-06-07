# frozen_string_literal: true

class TournamentPrediction < ApplicationRecord
  PODIUM_SPOTS = %i[champion runner_up third_place fourth_place].freeze

  has_paper_trail

  belongs_to :user
  belongs_to :tournament
  belongs_to :champion,     class_name: "Team",   optional: true
  belongs_to :runner_up,    class_name: "Team",   optional: true
  belongs_to :third_place,  class_name: "Team",   optional: true
  belongs_to :fourth_place, class_name: "Team",   optional: true
  belongs_to :top_scorer,   class_name: "Player", optional: true

  has_one :tournament_prediction_score, dependent: :destroy

  validate :podium_spots_are_distinct
  validate :podium_teams_belong_to_tournament
  validate :top_scorer_belongs_to_tournament

  def locked?
    return true if locked_at.present?

    tournament.predictions_locked?
  end

  private

  def podium_spot_ids
    [ champion_id, runner_up_id, third_place_id, fourth_place_id ].compact
  end

  def podium_spots_are_distinct
    ids = podium_spot_ids
    return if ids.uniq.length == ids.length

    errors.add(:base, :duplicate_podium)
  end

  # Participation (the team plays a match of the fixture), not the mere
  # tournament tag — seed leftovers tagged to the tournament are not pickable.
  def podium_teams_belong_to_tournament
    return if tournament.nil?

    PODIUM_SPOTS.each do |spot|
      team = public_send(spot)
      next if team.nil? || tournament.participating_team_ids.include?(team.id)

      errors.add(:"#{spot}_id", :not_in_tournament)
    end
  end

  def top_scorer_belongs_to_tournament
    return if top_scorer.nil? || tournament.nil?
    # Through the association (not the raw FK) so not-yet-saved graphs resolve.
    return if tournament.participating_team_ids.include?(top_scorer.team&.id)

    errors.add(:top_scorer_id, :not_in_tournament)
  end
end
