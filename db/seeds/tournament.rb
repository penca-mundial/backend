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
      tournament = ::Tournament.find_or_create_by!(name: NAME) do |t|
        t.starts_at = STARTS_AT
        t.ends_at   = ENDS_AT
      end
      # Idempotently backfill the competition code (added in SCRUM-262) on both
      # fresh and pre-existing rows.
      tournament.update!(external_code: EXTERNAL_CODE) if tournament.external_code != EXTERNAL_CODE
      tournament
    end
  end
end
