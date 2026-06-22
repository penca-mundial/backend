# frozen_string_literal: true

module Brackets
  # The Round-of-32 (dieciseisavos) PROJECTED for one user: each cross of the
  # first knockout round filled from that user's projected group positions
  # (real results where played, their predictions elsewhere — ADR-0005), so the
  # SPA can draw "según tus pronósticos" before the real bracket is confirmed.
  # Only the first round; later rounds are out of scope (SCRUM-319).
  #
  # Per slot (from OrderTable, keyed by Tournament#external_code):
  #   * real wins — if a real first-round Match is already anchored to this slot's
  #     bracket_position, its teams are used (source: "real").
  #   * otherwise a determinate side ({group, position}) resolves to that group's
  #     projected team at that rank, but ONLY when unambiguous; a "best third"
  #     side ({position: 3}, group-agnostic) and any ambiguous/missing rank
  #     resolve to null ("A definir"). (source: "projected")
  #
  # Ambiguity: a rank is ambiguous when its projected row ties (same points, goal
  # difference, goals-for) with the adjacent rank — the order between them is then
  # arbitrary, so the slot is left "A definir".
  #
  # Reuse, no duplication: positions come from ProjectedGroupStandingsQuery, slot
  # definitions and order from OrderTable, the real anchor from the builder's
  # bracket_position. Returns a ServiceResult:
  #   { projected: <bool>, round_of_32: [ { bracket_position, home, away, source } ] }
  class ProjectBracket < Service
    def initialize(tournament:, user:, order_table: :auto)
      @tournament = tournament
      @user = user
      @order_table = order_table == :auto ? OrderTable.from_file(tournament.external_code) : order_table
    end

    def call
      return success(projected: false, round_of_32: []) unless @order_table

      slots = @order_table.slots.sort_by(&:order).map { |slot| entry(slot) }
      success(projected: slots.any? { |slot| slot[:source] == "projected" }, round_of_32: slots)
    end

    private

    def entry(slot)
      real = real_by_position[slot.order]
      return real_entry(slot.order, real) if real

      home, away = slot.sides
      {
        bracket_position: slot.order,
        home:   resolve(home),
        away:   resolve(away),
        source: "projected"
      }
    end

    def real_entry(order, match)
      {
        bracket_position: order,
        home:   team_hash(match.home_team),
        away:   team_hash(match.away_team),
        source: "real"
      }
    end

    # A determinate side resolves to its group's projected team at that rank, but
    # only when unambiguous. A group-less side (best third) is always "A definir".
    def resolve(side)
      return nil if side[:group].nil?

      rows = projected_rows[side[:group]]
      return nil if rows.nil?

      position = side[:position]
      row = rows[position - 1]
      return nil if row.nil? || ambiguous?(rows, position)

      team_hash(row.team)
    end

    # Tie with the rank just above or below -> the order is arbitrary -> ambiguous.
    def ambiguous?(rows, position)
      current = rows[position - 1]
      previous = position >= 2 ? rows[position - 2] : nil
      following = rows[position] # 0-indexed `position` is the next rank
      [ previous, following ].compact.any? { |row| rank_key(row) == rank_key(current) }
    end

    def rank_key(row)
      [ row.points, row.goal_difference, row.goals_for ]
    end

    def team_hash(team)
      team && TeamBlueprint.render_as_hash(team)
    end

    # group name => the group's projected rows, ranked (ProjectedGroupStandingsQuery).
    def projected_rows
      @projected_rows ||= ProjectedGroupStandingsQuery
        .call(tournament: @tournament, user: @user)
        .to_h { |group| [ group.name, group.standings ] }
    end

    # Real first-round matches already anchored by the builder, keyed by their
    # bracket_position — the join that lets a confirmed cross win over the projection.
    def real_by_position
      @real_by_position ||= @tournament.matches
        .where(phase: @order_table.first_round)
        .where.not(bracket_position: nil)
        .includes(:home_team, :away_team)
        .index_by(&:bracket_position)
    end
  end
end
