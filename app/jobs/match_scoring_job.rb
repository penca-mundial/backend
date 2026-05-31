# frozen_string_literal: true

class MatchScoringJob < ApplicationJob
  queue_as :default

  # TODO: real scoring logic implemented in SCRUM-137 (Phase 5). For now this is
  # a no-op enqueued by SyncMatch when a match transitions to 'finished'.
  def perform(_match_id); end
end
