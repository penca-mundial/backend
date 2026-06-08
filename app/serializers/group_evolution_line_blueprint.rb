# frozen_string_literal: true

# One chart line for the per-penca evolution endpoint: the user identity plus
# their { date, points, rank } series. The objects are
# GroupEvolutionQuery::Line structs (not AR records).
class GroupEvolutionLineBlueprint < Blueprinter::Base
  field :user do |line|
    { id: line.user_id, username: line.username, avatar_url: line.avatar_url }
  end

  field :series do |line|
    line.series
  end
end
