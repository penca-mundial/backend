# frozen_string_literal: true

# The one tournament every record hangs off of. Times are anchored in UTC; the
# frontend handles user-timezone display.
module Seeds
  module Tournament
    NAME      = "FIFA World Cup 2026"
    STARTS_AT = Time.utc(2026, 6, 11, 16, 0, 0)
    ENDS_AT   = Time.utc(2026, 7, 19, 19, 0, 0)

    def self.call
      ::Tournament.find_or_create_by!(name: NAME) do |tournament|
        tournament.starts_at = STARTS_AT
        tournament.ends_at   = ENDS_AT
      end
    end
  end
end
