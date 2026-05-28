# frozen_string_literal: true

class Tournament < ApplicationRecord
  belongs_to :champion,     class_name: "Team",   optional: true
  belongs_to :runner_up,    class_name: "Team",   optional: true
  belongs_to :third_place,  class_name: "Team",   optional: true
  belongs_to :fourth_place, class_name: "Team",   optional: true
  belongs_to :top_scorer,   class_name: "Player", optional: true

  has_many :teams
  has_many :matches
  has_many :players, through: :teams

  validates :name, :starts_at, :ends_at, presence: true
end
