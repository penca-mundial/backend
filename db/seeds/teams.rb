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
        # Reconcile by code3 (the stable FIFA key shared with the API), mirroring
        # FootballData::SyncFixtures#upsert_team. Keying on the placeholder
        # external_id would miss a bootstrapped row and try to insert a duplicate
        # code3, violating the (tournament_id, code3) unique index.
        team = ::Team.find_or_initialize_by(tournament: tournament, code3: attrs.fetch("code3"))
        # The curated (Spanish) name is authoritative — it wins even over the
        # API name a bootstrap may have written.
        team.name = attrs.fetch("name")
        # Seed the placeholder external_id only on fresh rows; never clobber the
        # real football-data numeric id (or the API-owned flag_url) set by bootstrap.
        team.external_id = attrs.fetch("external_id") if team.new_record?
        team.save!
      end
    end

    def self.load_data
      YAML.safe_load_file(DATA_PATH)
    end
  end
end
