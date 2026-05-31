# frozen_string_literal: true

class Team < ApplicationRecord
  belongs_to :tournament

  has_many :players
  has_many :standings
  has_many :home_matches, class_name: "Match", foreign_key: :home_team_id
  has_many :away_matches, class_name: "Match", foreign_key: :away_team_id

  validates :name, presence: true
  validates :code3, presence: true, length: { is: 3 }
  validates :external_id, presence: true, uniqueness: true
end
