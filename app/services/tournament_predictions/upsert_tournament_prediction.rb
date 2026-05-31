# frozen_string_literal: true

module TournamentPredictions
  # Creates or updates a user's single tournament-wide prediction (podium +
  # top scorer). The only time-based rule lives here — the prediction closes at
  # kickoff of the tournament and is irrevocable after that. The podium-distinct,
  # teams-belong-to-tournament and top-scorer-belongs rules are TournamentPrediction
  # model validations, enforced here via update! (a failed save bubbles up as a
  # ServiceResult failure). All team/player ids are optional (partial picks are OK).
  class UpsertTournamentPrediction < Service
    def initialize(user:, tournament:, champion_id: nil, runner_up_id: nil,
                   third_place_id: nil, fourth_place_id: nil, top_scorer_id: nil)
      @user = user
      @tournament = tournament
      @attributes = {
        champion_id: champion_id,
        runner_up_id: runner_up_id,
        third_place_id: third_place_id,
        fourth_place_id: fourth_place_id,
        top_scorer_id: top_scorer_id
      }
    end

    def call
      raise_service_error("El torneo ya comenzó; el pronóstico está cerrado.") if @tournament.starts_at <= Time.current

      prediction = TournamentPrediction.find_or_initialize_by(user: @user, tournament: @tournament)
      prediction.update!(@attributes)
      success(prediction)
    end
  end
end
