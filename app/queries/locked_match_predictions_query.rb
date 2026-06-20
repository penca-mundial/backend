# frozen_string_literal: true

# The target user's match predictions that are already LOCKED (finished + the
# current live match), for the public profile feed. The fairness gate is applied
# HERE, before anything is serialized: a prediction for a still-open match never
# leaves this query.
#
# The authoritative gate is Prediction#locked? evaluated in Ruby, so the
# 1-minute kickoff buffer and the locked_at flag match the rest of the app
# exactly (no drifting SQL re-implementation). The candidate set is the user's
# predictions for the tournament, team-preloaded so the scoreboard that consumes
# the matches stays N+1-free regardless of how many finished matches exist.
#
# Ordering: the live match is always first (so it lands on page 1), then by
# kickoff descending (most recent first). Pagination is applied to the gated,
# ordered list and returns a Page with the slice plus has_more.
class LockedMatchPredictionsQuery < ApplicationQuery
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  Page = Struct.new(:matches, :page, :has_more, keyword_init: true)

  def initialize(user:, tournament:, page: 1, per_page: DEFAULT_PER_PAGE)
    @user = user
    @tournament = tournament
    @page = page.positive? ? page : 1
    @per_page = per_page.clamp(1, MAX_PER_PAGE)
  end

  def call
    matches = ordered_matches
    offset = (@page - 1) * @per_page
    window = matches[offset, @per_page] || []
    Page.new(matches: window, page: @page, has_more: matches.size > offset + window.size)
  end

  private

  # Gated matches (live first, then kickoff desc). The gate is Prediction#locked?
  # in Ruby — open-match predictions are dropped before serialization.
  def ordered_matches
    locked_predictions
      .map(&:match)
      .sort_by { |match| [ match.status_live? ? 0 : 1, -match.kickoff_at.to_i ] }
  end

  def locked_predictions
    candidate_predictions.select(&:locked?)
  end

  # The user's predictions for this tournament's matches, with teams preloaded.
  # references(:matches) makes includes use a single LEFT JOIN so the filter and
  # the preload share one query.
  def candidate_predictions
    @user.predictions
         .includes(match: [ :home_team, :away_team ])
         .where(matches: { tournament_id: @tournament.id })
         .references(:matches)
  end
end
