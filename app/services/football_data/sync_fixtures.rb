# frozen_string_literal: true

module FootballData
  # One-shot, idempotent sync that populates the tournament's Teams, Players and
  # Matches from football-data.org. Re-running updates existing rows (matched by
  # external_id) instead of duplicating them. The whole sync runs in a single
  # transaction: if any row is invalid, nothing is persisted.
  #
  # Returns a ServiceResult whose data is the synced counts:
  #   { teams_synced:, players_synced:, matches_synced: }
  class SyncFixtures < Service
    # football-data.org status -> Match status enum.
    STATUS_MAP = {
      "SCHEDULED" => "scheduled", "TIMED" => "scheduled",
      "IN_PLAY" => "live", "PAUSED" => "live",
      "FINISHED" => "finished", "AWARDED" => "finished",
      "POSTPONED" => "postponed",
      "SUSPENDED" => "cancelled", "CANCELLED" => "cancelled"
    }.freeze

    # football-data.org stage -> Match phase enum.
    PHASE_MAP = {
      "GROUP_STAGE" => "group_stage",
      "LAST_32" => "round_of_32",
      "LAST_16" => "round_of_16",
      "QUARTER_FINALS" => "quarter_final",
      "SEMI_FINALS" => "semi_final",
      "THIRD_PLACE" => "third_place",
      "FINAL" => "final"
    }.freeze

    def initialize(client: Client.new, competition_code: Client::WORLD_CUP_CODE)
      @client = client
      @code = competition_code
      @teams_by_external_id = {}
    end

    def call
      counts = { teams_synced: 0, players_synced: 0, matches_synced: 0 }

      ActiveRecord::Base.transaction do
        sync_competition_info
        counts[:teams_synced], counts[:players_synced] = sync_teams_and_players
        counts[:matches_synced] = sync_matches
      end

      success(counts)
    end

    private

    def tournament
      @tournament ||= Tournament.first!
    end

    # Refresh the tournament's name/dates from the competition payload.
    def sync_competition_info
      info = @client.competition(@code)
      tournament.name = info["name"] if info["name"].present?
      if (season = info["currentSeason"])
        tournament.starts_at = Time.zone.parse(season["startDate"]) if season["startDate"].present?
        tournament.ends_at = Time.zone.parse(season["endDate"]) if season["endDate"].present?
      end
      tournament.save!
    end

    def sync_teams_and_players
      teams = 0
      players = 0

      @client.competition_teams(@code).fetch("teams", []).each do |data|
        team = upsert_team(data)
        @teams_by_external_id[team.external_id] = team
        teams += 1
        players += sync_squad(team, data["squad"] || [])
      end

      [ teams, players ]
    end

    # Reconcile by code3 (the FIFA key shared between db:seed and the API), NOT
    # by external_id: seeded teams carry a placeholder external_id
    # ("wc2026-<code>"), so matching on it would miss the row and try to insert a
    # duplicate, violating the (tournament_id, code3) unique index. We always
    # overwrite external_id (placeholder -> football-data numeric id) and the
    # API-owned flag_url, but preserve the seed's curated (Spanish) name; a team
    # created fresh (bootstrap without seed) takes the API name.
    def upsert_team(data)
      team = Team.find_or_initialize_by(tournament: tournament, code3: data["tla"])
      team.name = data["name"] if team.new_record?
      team.external_id = data["id"].to_s
      team.flag_url = data["crest"]
      team.save!
      team
    end

    def sync_squad(team, squad)
      squad.each do |data|
        player = Player.find_or_initialize_by(external_id: data["id"].to_s)
        player.update!(team: team, name: data["name"])
      end
      squad.size
    end

    def sync_matches
      synced = 0
      @client.competition_matches(@code).fetch("matches", []).each do |data|
        synced += 1 if upsert_match(data)
      end
      synced
    end

    # Skips matches whose teams are not (yet) known — knockout slots are often
    # TBD in the feed until the bracket fills in.
    def upsert_match(data)
      home = team_for(data.dig("homeTeam", "id"))
      away = team_for(data.dig("awayTeam", "id"))
      return false if home.nil? || away.nil?

      score = data["score"]&.dig("fullTime") || {}
      match = Match.find_or_initialize_by(external_id: data["id"].to_s)
      match.update!(
        tournament: tournament,
        home_team: home,
        away_team: away,
        kickoff_at: Time.zone.parse(data["utcDate"]),
        status: STATUS_MAP.fetch(data["status"], "scheduled"),
        phase: PHASE_MAP.fetch(data["stage"], "group_stage"),
        group: normalize_group(data["group"]),
        home_score: score["home"] || 0,
        away_score: score["away"] || 0
      )
      true
    end

    # Normalize the API's group identifier to a short token: "GROUP_A" -> "A",
    # "Group A" -> "A", "A" -> "A". Returns nil when absent or empty (knockout
    # matches have no group). The result is NOT constrained to A-L — whatever the
    # upstream returns post-normalization is stored, so tournaments with a
    # different number of groups or labels work without code changes.
    def normalize_group(raw)
      return nil if raw.blank?

      raw.to_s.strip.sub(/\AGROUP[\s_]*/i, "").strip.presence
    end

    def team_for(external_id)
      return nil if external_id.nil?

      @teams_by_external_id[external_id.to_s]
    end
  end
end
