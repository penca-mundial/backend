# frozen_string_literal: true

class Player < ApplicationRecord
  belongs_to :team

  has_one :tournament, through: :team

  validates :name, presence: true
  validates :external_id, uniqueness: { allow_nil: true }
end
