# frozen_string_literal: true

module Scoring
  # Orchestrates the tournament-wide scoring: resolves the five real results
  # once, evaluates every TournamentPrediction with TournamentRuleEvaluator
  # (SCRUM-138), maps each correct dimension to its ScoringRule points (NO phase
  # multiplier — these are global predictions), and upserts a
  # TournamentPredictionScore per user.
  #
  # Runs once when the tournament is finalized (trigger is SCRUM-140). Idempotent
  # via the unique index on tournament_prediction_id.
  #
  # Returns a ServiceResult with { count: <predictions scored> }.
  class ComputeTournamentScores < Service
    # Evaluator boolean (== ScoringRule key) -> TournamentPredictionScore column.
    # Note third/fourth map to points_third / points_fourth.
    COMPONENT_RULES = {
      champion_correct:     :points_champion,
      runner_up_correct:    :points_runner_up,
      third_place_correct:  :points_third,
      fourth_place_correct: :points_fourth,
      top_scorer_correct:   :points_top_scorer
    }.freeze

    def initialize(tournament:, client: Client.new)
      @tournament = tournament
      @client = client
      @points_cache = {}
    end

    def call
      results = resolve_results
      # Persist the real podium + top scorer on the Tournament so the public
      # projection (TournamentBlueprint) has a single source of truth. The
      # result keys match the column names exactly; unresolved dimensions are
      # nil. Idempotent.
      @tournament.update!(results)

      count = 0
      @tournament.tournament_predictions.find_each do |prediction|
        score_prediction(prediction, results)
        count += 1
      end

      success(count: count)
    end

    private

    # The five real result ids, resolved once. Each may be nil when its source
    # isn't available yet (missing/unfinished match, no advancing team, top
    # scorer not mapped) — TournamentRuleEvaluator treats nil as a miss.
    def resolve_results
      champion_id, runner_up_id = podium_for("final")
      third_place_id, fourth_place_id = podium_for("third_place")

      {
        champion_id:     champion_id,
        runner_up_id:    runner_up_id,
        third_place_id:  third_place_id,
        fourth_place_id: fourth_place_id,
        top_scorer_id:   real_top_scorer_id
      }
    end

    # [winner_team_id, loser_team_id] for a finished match of the given phase
    # that has an advancing team; [nil, nil] when the match is missing, not
    # finished, or has no advancing team (all anomalous → no podium points).
    def podium_for(phase)
      match = @tournament.matches.find_by(phase: phase)
      return [ nil, nil ] unless match&.status_finished? && match.advancing_team_id

      winner = match.advancing_team_id
      loser = [ match.home_team_id, match.away_team_id ].find { |id| id != winner }
      [ winner, loser ]
    end

    # The leading scorer mapped to our Player by external_id, or nil (no code,
    # empty list, or no matching Player).
    def real_top_scorer_id
      return nil if @tournament.external_code.blank?

      external_id = @client.scorers(@tournament.external_code)["scorers"]&.first&.dig("player", "id")
      return nil if external_id.nil?

      Player.find_by(external_id: external_id.to_s)&.id
    end

    def score_prediction(prediction, results)
      flags = invoke { TournamentRuleEvaluator.call(prediction: prediction, **results) }

      attributes = COMPONENT_RULES.to_h do |rule, column|
        [ column, flags[rule] ? points_for(rule) : 0 ]
      end
      attributes[:computed_at] = Time.current

      score = TournamentPredictionScore.find_or_initialize_by(tournament_prediction_id: prediction.id)
      score.assign_attributes(attributes)
      # total_points is derived by TournamentPredictionScore's before_save.
      score.save!
    end

    # Data-driven, memoized per rule. key? guards so a memoized 0 isn't re-queried.
    def points_for(rule)
      return @points_cache[rule] if @points_cache.key?(rule)

      @points_cache[rule] = ScoringRule.for(rule) || 0
    end
  end
end
