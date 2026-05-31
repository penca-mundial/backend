# frozen_string_literal: true

module FootballData
  # Normalizes the upstream group identifier to a short token:
  #   "GROUP_A" -> "A", "Group A" -> "A", "A" -> "A".
  # Returns nil for blank/absent input — knockout rounds and single-table
  # leagues have no group. The result is NOT constrained to A-L: whatever the
  # upstream returns post-normalization is kept, so tournaments with a different
  # number of groups or different labels work without code changes.
  #
  # Shared by FootballData::SyncFixtures (group on matches, SCRUM-257) and
  # FootballData::SyncStandings (group on standings, SCRUM-262) so both store the
  # `group` field identically.
  module GroupNormalizer
    module_function

    def call(raw)
      return nil if raw.blank?

      raw.to_s.strip.sub(/\AGROUP[\s_]*/i, "").strip.presence
    end
  end
end
