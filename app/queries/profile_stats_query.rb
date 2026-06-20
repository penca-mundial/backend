# frozen_string_literal: true

# Aggregate prediction accuracy for a user in one tournament, derived from the
# stored PredictionScore rows (breakdown->>'result_rule'). Only SCORED matches
# count — a PredictionScore exists exactly for finished, computed matches, so a
# live match (no score row yet) is naturally excluded from the stats even though
# its pick shows in the profile feed.
#
# The five buckets map the exhaustive result_rule values produced by
# Scoring::MatchRuleEvaluator:
#   exact            <- exact_score
#   correct_winner   <- correct_winner
#   goal_difference  <- correct_goal_difference
#   missed           <- no_match
#   total            <- sum of the above (every scored pick falls in one bucket)
class ProfileStatsQuery < ApplicationQuery
  RULE_TO_STAT = {
    "exact_score"             => :exact,
    "correct_winner"          => :correct_winner,
    "correct_goal_difference" => :goal_difference,
    "no_match"                => :missed
  }.freeze

  def initialize(user:, tournament:)
    @user = user
    @tournament = tournament
  end

  def call
    stats = { exact: 0, correct_winner: 0, goal_difference: 0, missed: 0 }

    counts_by_rule.each do |rule, count|
      key = RULE_TO_STAT[rule]
      stats[key] += count if key
    end

    stats.merge(total: stats.values.sum)
  end

  private

  def counts_by_rule
    PredictionScore
      .joins(prediction: :match)
      .where(predictions: { user_id: @user.id }, matches: { tournament_id: @tournament.id })
      .group(Arel.sql("prediction_scores.breakdown->>'result_rule'"))
      .count
  end
end
