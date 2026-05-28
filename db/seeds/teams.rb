# frozen_string_literal: true

require "yaml"

# Seeds the 48 World Cup teams from a static YAML list. Keyed by external_id
# (a `wc2026-<code>` placeholder) so that the Phase 3 SyncFixtures service can
# later rewrite name / code3 / flag_url against football-data.org without
# creating duplicate rows.
module Seeds
  module Teams
    DATA_PATH = Rails.root.join("db/seeds/data/teams.yml")

    def self.call
      tournament = ::Tournament.find_by!(name: Seeds::Tournament::NAME)

      load_data.each do |attrs|
        ::Team.find_or_create_by!(external_id: attrs.fetch("external_id")) do |team|
          team.tournament = tournament
          team.name       = attrs.fetch("name")
          team.code3      = attrs.fetch("code3")
        end
      end
    end

    def self.load_data
      YAML.safe_load_file(DATA_PATH)
    end
  end
end
