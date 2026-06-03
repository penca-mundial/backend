# frozen_string_literal: true

# The one tournament every record hangs off of. Times are anchored in UTC; the
# frontend handles user-timezone display.
module Seeds
  module Tournament
    NAME          = "FIFA World Cup 2026"
    STARTS_AT     = Time.utc(2026, 6, 11, 16, 0, 0)
    ENDS_AT       = Time.utc(2026, 7, 19, 19, 0, 0)
    EXTERNAL_CODE = "WC" # football-data.org competition code

    def self.call
      # Identity is external_code (the competition code), never name — so the
      # seed converges with FootballData::SyncFixtures regardless of run order
      # and never creates a duplicate tournament (cf. teams-by-code3, SCRUM-256).
      tournament = ::Tournament.find_or_initialize_by(external_code: EXTERNAL_CODE)
      # The seed OWNS the name: set the curated name on every run, even over an
      # API name a prior bootstrap may have written.
      tournament.name = NAME
      # Seed the dates only when missing, so a bootstrap's real API dates survive.
      tournament.starts_at ||= STARTS_AT
      tournament.ends_at   ||= ENDS_AT
      tournament.save!
      tournament
    end
  end
end
