# frozen_string_literal: true

module Brackets
  # The canonical vertical order of the FIRST knockout round, curated per
  # competition (data, not logic). Lives in db/seeds/data/brackets/<code>.yml and
  # is keyed by Tournament#external_code, so nothing here is World-Cup specific.
  #
  # Each slot fixes one cross of the first round, top-to-bottom (order 0..N-1),
  # identified by the (group, position) of its sides. The non-determinate side of
  # a "vs best third" cross is written as `{ position: 3 }` with NO group: the
  # identity of which third lands there (FIFA Annex C) is irrelevant to the
  # ORDER, so the 495-scenario table is deliberately not modelled. The
  # determinate side (a specific group winner/runner-up) is unique across slots,
  # so a real match anchors to exactly one slot.
  #
  # Only the first round needs the table; later rounds derive their position from
  # the feeds_into graph (Brackets::BuildTopology).
  class OrderTable
    Slot = Struct.new(:order, :sides, keyword_init: true)

    BRACKETS_DIR = "db/seeds/data/brackets"

    # The slot definitions (order + normalized sides) and the phase of the first
    # knockout round. `slots`/`first_round` are read by the projected-bracket
    # service (SCRUM-319) to BUILD crosses from group positions — the forward
    # direction, vs position_for's lookup; first_round keeps which round that is
    # data-driven (never hard-coded).
    attr_reader :slots, :first_round

    # The table for a competition code, or nil when no curated file exists (the
    # builder then wires edges but leaves bracket_position alone).
    def self.from_file(external_code)
      return nil if external_code.blank?

      path = Rails.root.join(BRACKETS_DIR, "#{external_code.downcase}.yml")
      return nil unless File.exist?(path)

      data = YAML.safe_load_file(path)
      new(slots: data.fetch("slots"), first_round: data["first_round"])
    end

    def initialize(slots:, first_round: nil)
      @first_round = first_round
      @slots = slots.map do |slot|
        Slot.new(order: slot.fetch("order"), sides: slot.fetch("sides").map { |side| normalize(side) })
      end
    end

    def orders
      @slots.map(&:order)
    end

    # The canonical order for the match whose two teams carry the given
    # { group:, position: } metas, or nil when no slot fits — a signal that the
    # locally computed group positions disagree with the bracket the feed built
    # (surfaced by the builder as a visible warning).
    def position_for(meta_a, meta_b)
      @slots.find { |slot| slot_matches?(slot, meta_a, meta_b) }&.order
    end

    private

    def normalize(side)
      { group: side["group"], position: side.fetch("position") }
    end

    def slot_matches?(slot, meta_a, meta_b)
      first, second = slot.sides
      (side_ok?(meta_a, first) && side_ok?(meta_b, second)) ||
        (side_ok?(meta_a, second) && side_ok?(meta_b, first))
    end

    # A side matches when the position lines up and, for a determinate side, the
    # group too. A group-less side ({ position: 3 }) matches any third.
    def side_ok?(meta, side)
      return false if meta.nil? || meta[:position] != side[:position]

      side[:group].nil? || meta[:group] == side[:group]
    end
  end
end
