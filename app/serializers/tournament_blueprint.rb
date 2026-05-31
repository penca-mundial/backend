# frozen_string_literal: true

# Public tournament projection. Exposes the result FK ids as plain ids (all
# nullable — pre-tournament they are nil); embedding the champion/top-scorer
# teams is deferred until a consumer needs it (open/closed). Adds two derived
# fields the SPA uses to gate the prediction UI.
class TournamentBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :starts_at, :ends_at, :external_code,
         :champion_id, :runner_up_id, :third_place_id, :fourth_place_id, :top_scorer_id

  # Predictions lock once the tournament has kicked off.
  field(:is_locked) { |tournament| tournament.starts_at <= Time.current }

  # Countdown to kickoff in seconds; clamped at 0 once started.
  field(:seconds_until_kickoff) { |tournament| [ (tournament.starts_at - Time.current).to_i, 0 ].max }
end
