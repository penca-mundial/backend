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
      "EXTRA_TIME" => "live", "PENALTY_SHOOTOUT" => "live",
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

    def initialize(client: Client.new, competition_code: Client::WORLD_CUP_CODE, incremental: false)
      @client = client
      @code = competition_code
      @incremental = incremental
      @teams_by_external_id = {}
    end

    # Full bootstrap (competition info + teams + players + every resolvable
    # match) or, when incremental: true, the lightweight recurring re-sync that
    # only creates newly-resolved matches and refreshes inert metadata. See
    # #incremental_sync / #upsert_match.
    def call
      return incremental_sync if @incremental

      counts = { teams_synced: 0, players_synced: 0, matches_synced: 0 }

      ActiveRecord::Base.transaction do
        sync_competition_info
        counts[:teams_synced], counts[:players_synced] = sync_teams_and_players
        counts[:matches_synced] = sync_matches
      end

      success(counts)
    end

    private

    # Recurring "create-on-resolve" pass (ADR-0001): no competition/teams API
    # calls — teams come from the DB — and matches whose teams are still TBD in
    # the feed are skipped. Creates each knockout match once the feed names both
    # teams; the live state of existing matches is left to SyncMatch.
    def incremental_sync
      @teams_by_external_id = tournament.teams.index_by(&:external_id)
      created = 0
      @client.competition_matches(@code).fetch("matches", []).each do |data|
        created += 1 if upsert_match(data)
      end
      success(matches_created: created)
    end

    # The tournament for the competition being synced, reconciled by its stable
    # identity — external_code (the competition code, e.g. "WC") — never by name.
    # This makes bootstrap and db:seed converge on a single row in any order
    # (mirrors teams-by-code3, SCRUM-256). Built unsaved here; sync_competition_info
    # fills the required attributes and persists it (creating it on first bootstrap).
    def tournament
      @tournament ||= Tournament.find_or_initialize_by(external_code: @code)
    end

    # Refresh the tournament's dates from the competition payload and persist it.
    # The curated name belongs to db:seed, so we only fall back to the API name
    # when creating a brand-new row — an existing name is never overwritten.
    def sync_competition_info
      info = @client.competition(@code)
      tournament.name = info["name"] if tournament.new_record? && info["name"].present?
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
    # TBD in the feed until the bracket fills in. In incremental mode an existing
    # match is only refreshed for inert metadata (#refresh_existing); its live
    # state is never touched.
    def upsert_match(data)
      home = team_for(data.dig("homeTeam", "id"))
      away = team_for(data.dig("awayTeam", "id"))
      return false if home.nil? || away.nil?

      match = Match.find_or_initialize_by(external_id: data["id"].to_s)
      return refresh_existing(match, data) if @incremental && match.persisted?

      # Users predict the 90-minute result; ET/penalties only decide who
      # advances. regularTime carries the post-90' score for ET/penalty matches;
      # matches settled in 90' (all of the group stage) have no regularTime and
      # fall back to fullTime — unchanged behavior there.
      score = data["score"] || {}
      result = score["regularTime"] || score["fullTime"] || {}
      status = STATUS_MAP.fetch(data["status"], "scheduled")
      phase = PHASE_MAP.fetch(data["stage"], "group_stage")

      match.update!(
        tournament: tournament,
        home_team: home,
        away_team: away,
        kickoff_at: Time.zone.parse(data["utcDate"]),
        status: status,
        phase: phase,
        group: GroupNormalizer.call(data["group"]),
        home_score: result["home"] || 0,
        away_score: result["away"] || 0,
        advancing_team_id: advancing_team_id_for(score, phase: phase, home: home, away: away,
                                                 status: status, external_id: data["id"])
      )
      true
    end

    # Incremental refresh of an existing match: only inert structural metadata
    # (kickoff_at — postponements far beyond the poller's 24h horizon). Never the
    # live state (status / scores / advancing_team_id / minute / events_log)
    # owned by SyncMatch. Returns false: this is not a creation.
    def refresh_existing(match, data)
      kickoff = Time.zone.parse(data["utcDate"]) if data["utcDate"].present?
      match.update!(kickoff_at: kickoff) if kickoff && kickoff != match.kickoff_at
      false
    end

    # Knockout advancing team from score.winner for a regulation / extra-time
    # result; nil for the group stage. A penalty shootout leaves winner nil
    # (football-data does not populate it), so it's resolved from the shootout
    # aggregate once finished. Mirrors SyncMatch#advancing_team_id_from.
    def advancing_team_id_for(score, phase:, home:, away:, status:, external_id:)
      return nil if phase == "group_stage"

      case score["winner"]
      when "HOME_TEAM" then home.id
      when "AWAY_TEAM" then away.id
      else
        shootout_advancing_team_id_for(score, home: home, away: away, status: status, external_id: external_id)
      end
    end

    # Penalty-shootout winner, resolved only once the match is finished: prefer the
    # penalties field, fall back to the penalty-inclusive fullTime when penalties are
    # absent or tied. nil (logged) for a finished KO that still resolves to nobody.
    def shootout_advancing_team_id_for(score, home:, away:, status:, external_id:)
      return nil unless status == "finished"

      %w[penalties fullTime].each do |key|
        side = score[key] || {}
        h, a = side["home"], side["away"]
        next unless h && a && h != a

        return h > a ? home.id : away.id
      end

      log_warn("KO match #{external_id} finished without a resolvable winner: #{score["winner"].inspect}")
      nil
    end

    def team_for(external_id)
      return nil if external_id.nil?

      @teams_by_external_id[external_id.to_s]
    end
  end
end
