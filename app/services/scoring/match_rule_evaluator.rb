# frozen_string_literal: true

module Scoring
  # Pure rule classifier for a finished match. Given a Prediction and its Match,
  # it reports which scoring rule applies on each dimension. No DB writes — the
  # rule-symbol -> points lookup is ComputeMatchScores' job (SCRUM-136).
  #
  # Pre-condition: match.status_finished? (the caller guarantees it).
  #
  # Returns a ServiceResult whose data is:
  #   result_rule:  :exact_score | :correct_goal_difference | :correct_winner | :no_match
  #   advance_rule: :correct_advance | :no_advance | nil   (nil in the group stage)
  #
  # The result dimension is exclusive: the highest-ranking applicable rule wins
  # (exact_score > correct_goal_difference > correct_winner > no_match). The
  # rule symbols match ScoringRule's keys so the point mapping is a direct lookup.
  class MatchRuleEvaluator < Service
    def initialize(prediction:, match:)
      @prediction = prediction
      @match = match
    end

    def call
      success(result_rule: result_rule, advance_rule: advance_rule)
    end

    private

    def result_rule
      return :exact_score if exact?
      return :correct_goal_difference if same_goal_difference?
      return :correct_winner if same_outcome?

      :no_match
    end

    # Only knockout matches have an advancing team; the group stage has none.
    def advance_rule
      return nil if @match.phase_group_stage?

      correct_advance? ? :correct_advance : :no_advance
    end

    def exact?
      @prediction.predicted_home_score == @match.home_score &&
        @prediction.predicted_away_score == @match.away_score
    end

    def same_goal_difference?
      (@prediction.predicted_home_score - @prediction.predicted_away_score) ==
        (@match.home_score - @match.away_score)
    end

    def same_outcome?
      outcome(@prediction.predicted_home_score, @prediction.predicted_away_score) ==
        outcome(@match.home_score, @match.away_score)
    end

    def correct_advance?
      @prediction.predicted_advancing_team_id == @match.advancing_team_id
    end

    def outcome(home, away)
      return :home_win if home > away
      return :away_win if home < away

      :draw
    end
  end
end
