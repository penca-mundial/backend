# frozen_string_literal: true

require "yaml"

# Seeds the 48 World Cup teams from a static YAML list. `code3` (the FIFA
# three-letter code) is the stable natural key. `external_id "wc2026-<code>"` is
# a PLACEHOLDER: FootballData::SyncFixtures matches each team by `code3` on the
# first sync and overwrites `external_id` with the real football-data numeric id
# (and sets `flag_url`), while preserving the curated `name` seeded here. So
# these rows are reconciled in place — never duplicated.
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
