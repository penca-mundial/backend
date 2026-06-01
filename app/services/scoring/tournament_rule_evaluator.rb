# frozen_string_literal: true

module Scoring
  # Pure rule classifier for the tournament-wide prediction (podium + top
  # scorer). Given a TournamentPrediction and the tournament's REAL result ids,
  # it reports five INDEPENDENT booleans (unlike MatchRuleEvaluator's exclusive
  # result rule). No DB — the real ids are resolved by ComputeTournamentScores
  # (SCRUM-139) and passed in; the point lookup is its job too.
  #
  # Returns a ServiceResult whose data keys match ScoringRule's tournament rule
  # types so the mapping is direct:
  #   champion_correct, runner_up_correct, third_place_correct,
  #   fourth_place_correct, top_scorer_correct
  class TournamentRuleEvaluator < Service
    def initialize(prediction:, champion_id:, runner_up_id:, third_place_id:, fourth_place_id:, top_scorer_id:)
      @prediction = prediction
      @champion_id = champion_id
      @runner_up_id = runner_up_id
      @third_place_id = third_place_id
      @fourth_place_id = fourth_place_id
      @top_scorer_id = top_scorer_id
    end

    def call
      success(
        champion_correct:     correct?(@prediction.champion_id, @champion_id),
        runner_up_correct:    correct?(@prediction.runner_up_id, @runner_up_id),
        third_place_correct:  correct?(@prediction.third_place_id, @third_place_id),
        fourth_place_correct: correct?(@prediction.fourth_place_id, @fourth_place_id),
        top_scorer_correct:   correct?(@prediction.top_scorer_id, @top_scorer_id)
      )
    end

    private

    # A hit needs a real result AND a matching pick. A missing result, a missing
    # pick, or nil == nil all count as a miss — not predicting and/or no result
    # is never a hit.
    def correct?(predicted_id, real_id)
      real_id.present? && predicted_id == real_id
    end
  end
end
