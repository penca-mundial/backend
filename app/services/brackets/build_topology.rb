# frozen_string_literal: true

module Brackets
  # Populates the knockout bracket topology (feeds_into_match_id /
  # feeds_into_slot / bracket_position) for a tournament's matches, WITHOUT
  # modelling the crosses ourselves — football-data still owns who plays whom
  # (ADR-0001). We only wire the tree from data we already store:
  #
  #   * feeds_into edges: derived from advancing_team_id. When a round-N+1 match
  #     names team T, the round-N match whose advancing_team_id == T feeds that
  #     slot (home/away by which side T occupies). Deterministic, multi-tournament,
  #     no FIFA cross table, no Annex C, no group positions. Populated round by
  #     round, only once advancing_team is known (create-on-resolve friendly).
  #
  #   * bracket_position: the first knockout round is anchored to the curated
  #     canonical order (Brackets::OrderTable) by the group positions of each
  #     match's teams; every later round derives its position from its home-slot
  #     parent (child = parent / 2), walking the feeds_into graph already wired.
  #
  # Reconciliation: when a first-round match's computed positions fit no slot (our
  # simplified tie-breaks disagreeing with the bracket the feed built), it is
  # logged VISIBLY (log_warn) and skipped — never silently mis-anchored.
  #
  # Idempotent: every write goes through update_if_changed, so re-running on an
  # unchanged fixture persists nothing. feeds_into is only ever SET (when a child
  # is found), never cleared on a worse guess.
  #
  # Returns a ServiceResult with { edges:, positions: } (counts of rows changed).
  class BuildTopology < Service
    # The knockout rounds in progression order. third_place is intentionally
    # absent: it is a sink fed by the semi-final LOSERS (not advancing_team), so
    # it has no feeds_into edge and no derived position. Derived from
    # Match::PHASES so a tournament starting at a different first round still
    # works; nothing here is World-Cup specific.
    KO_CHAIN = (Match::PHASES - %w[group_stage third_place]).freeze

    def initialize(tournament:, order_table: :auto)
      @tournament = tournament
      @order_table = order_table == :auto ? OrderTable.from_file(tournament.external_code) : order_table
      @edges = 0
      @positions = 0
    end

    def call
      wire_edges
      anchor_first_round
      propagate_positions

      success(edges: @edges, positions: @positions)
    end

    private

    # Parent -> child edges from advancing_team, one round at a time.
    def wire_edges
      KO_CHAIN.each_cons(2) do |phase, next_phase|
        children = matches_in(next_phase)
        matches_in(phase).each do |parent|
          link_parent(parent, children)
        end
      end
    end

    def link_parent(parent, children)
      return if parent.advancing_team_id.nil?

      child = children.find { |c| [ c.home_team_id, c.away_team_id ].include?(parent.advancing_team_id) }
      return unless child

      slot = child.home_team_id == parent.advancing_team_id ? "home" : "away"
      update_if_changed(parent, { feeds_into_match_id: child.id, feeds_into_slot: slot }, :edges)
    end

    # First knockout round -> canonical order from the curated table, anchored by
    # the teams' group positions. Skipped (edges only) when no table is curated.
    def anchor_first_round
      return unless @order_table

      round = first_round
      return unless round

      @anchored_orders = {}
      matches_in(round).each { |match| anchor(match) }
    end

    def anchor(match)
      home = position_meta[match.home_team_id]
      away = position_meta[match.away_team_id]
      if home.nil? || away.nil?
        log_warn("bracket: match #{match.external_id} has a team with no computed group position; not anchored yet")
        return
      end

      order = @order_table.position_for(home, away)
      if order.nil?
        log_warn("bracket: could not anchor #{match.phase} match #{match.external_id} " \
                 "(#{home} vs #{away}) to any slot — computed positions disagree with the feed bracket")
        return
      end

      if @anchored_orders.key?(order)
        log_warn("bracket: slot #{order} claimed by both #{@anchored_orders[order]} and #{match.external_id} " \
                 "— computed positions inconsistent with the feed bracket")
      end
      @anchored_orders[order] = match.external_id

      update_if_changed(match, { bracket_position: order }, :positions)
    end

    # Later rounds: a match sits at half its home-slot parent's position, so each
    # parent aligns between its two children. Walked in round order so a round's
    # parents are positioned before it is read.
    def propagate_positions
      rounds_after_first.each do |phase|
        matches_in(phase).each do |match|
          parent = home_parent_of(match)
          next unless parent&.bracket_position

          update_if_changed(match, { bracket_position: parent.bracket_position / 2 }, :positions)
        end
      end
    end

    # The match feeding this one's HOME slot (its left child in the drawing).
    def home_parent_of(match)
      parents_by_child[match.id]&.find { |p| p.feeds_into_slot == "home" }
    end

    def parents_by_child
      @parents_by_child ||= ko_matches.group_by(&:feeds_into_match_id)
    end

    def first_round
      @first_round ||= KO_CHAIN.find { |phase| matches_in(phase).any? }
    end

    def rounds_after_first
      return [] unless first_round

      KO_CHAIN.drop(KO_CHAIN.index(first_round) + 1)
    end

    def matches_in(phase)
      matches_by_phase[phase] || []
    end

    def matches_by_phase
      @matches_by_phase ||= ko_matches.group_by(&:phase)
    end

    def ko_matches
      @ko_matches ||= @tournament.matches.where(phase: KO_CHAIN)
                                 .includes(:home_team, :away_team).to_a
    end

    # team_id => { group:, position: } from the locally computed group tables.
    def position_meta
      @position_meta ||= GroupStandingsQuery.call(tournament: @tournament).each_with_object({}) do |group, acc|
        group.standings.each { |row| acc[row.team.id] = { group: group.name, position: row.position } }
      end
    end

    def update_if_changed(record, attributes, counter)
      return if attributes.all? { |key, value| record.public_send(key) == value }

      record.update!(attributes)
      increment(counter)
    end

    def increment(counter)
      counter == :edges ? @edges += 1 : @positions += 1
    end
  end
end
