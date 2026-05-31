# frozen_string_literal: true

# Canonical resolver for "the current tournament" — the single source of truth
# the API (and, later, the Tournament.first! sites) use to pick one tournament
# without the client hardcoding an id.
#
# Precedence:
#   1. Active   — starts_at <= now <= ends_at; if several, the most recently
#                 started (matches the Tournament.active definition).
#   2. Upcoming — starts_at in the future; the soonest to start.
#   3. Past     — already ended; the most recently finished.
#   4. nil      — no tournaments at all.
#
# Deliberate, documented deviation from the list-query convention: this returns
# a single Tournament (or nil), not a chainable relation, because it is a
# resolver, not a filter.
class CurrentTournamentQuery < ApplicationQuery
  def call
    scope = relation || Tournament.all
    now = Time.current

    active(scope, now) || upcoming(scope, now) || most_recent_past(scope, now)
  end

  private

  def active(scope, now)
    scope.where(starts_at: ..now, ends_at: now..).order(starts_at: :desc).first
  end

  # Anything reaching this branch is not active, so starts_at >= now is
  # equivalent to strictly-future here.
  def upcoming(scope, now)
    scope.where(starts_at: now..).order(starts_at: :asc).first
  end

  def most_recent_past(scope, now)
    scope.where(ends_at: ...now).order(ends_at: :desc).first
  end
end
