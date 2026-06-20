# frozen_string_literal: true

module Profiles
  # The target user's locked match predictions (finished + the live match) for
  # the public profile feed, paginated. The lock gate lives in
  # LockedMatchPredictionsQuery — an open-match pick can never reach this service,
  # so nothing here has to hide anything.
  #
  # Each card reuses Matches::UserScoreboard (the target's pick + the points it
  # scores against the match's current score). The scoreboard labels the pick
  # `my_prediction` (it normally serves the requester's own matches); here the
  # matches belong to the VIEWED user, so it is relabeled `prediction`.
  #
  # Returns { entries:, page:, has_more: }.
  class ListLockedPredictions < Service
    def initialize(target:, tournament:, page: 1, per_page: LockedMatchPredictionsQuery::DEFAULT_PER_PAGE)
      @target = target
      @tournament = tournament
      @page = page
      @per_page = per_page
    end

    def call
      page = LockedMatchPredictionsQuery.call(
        user: @target, tournament: @tournament, page: @page, per_page: @per_page
      )

      success(entries: entries(page.matches), page: page.page, has_more: page.has_more)
    end

    private

    def entries(matches)
      Matches::UserScoreboard.call(matches: matches, user: @target).data[:entries].map do |entry|
        entry.except(:my_prediction).merge(prediction: entry[:my_prediction])
      end
    end
  end
end
