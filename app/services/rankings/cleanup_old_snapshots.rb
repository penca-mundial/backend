# frozen_string_literal: true

module Rankings
  # Prunes RankingSnapshot rows older than the retention window to keep the table
  # small. Pure retention: it sweeps EVERY old snapshot regardless of tournament
  # or group — not scoped.
  #
  # Uses a relative window (Time.current - retention_days) so there is no
  # timezone-boundary edge, and a strict `<` so a row exactly at the cutoff is
  # kept. delete_all (not destroy_all): a bulk sweep, no per-row callbacks.
  #
  # Returns a ServiceResult with { count: <rows deleted> }.
  class CleanupOldSnapshots < Service
    DEFAULT_RETENTION_DAYS = 60

    def initialize(retention_days: DEFAULT_RETENTION_DAYS)
      @retention_days = retention_days
    end

    def call
      cutoff = @retention_days.days.ago
      count = RankingSnapshot.where("snapshot_at < ?", cutoff).delete_all
      success(count: count)
    end
  end
end
