# frozen_string_literal: true

# One leaderboard row. The objects are LeaderboardQuery::Row structs (not AR
# records), so each field reads straight off the struct.
class RankingEntryBlueprint < Blueprinter::Base
  fields :user_id, :username, :avatar_url, :points, :exact_count, :rank_position
end
