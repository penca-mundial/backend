# frozen_string_literal: true

# Public tournament projection. Exposes the result FK ids as plain ids (all
# nullable — pre-tournament they are nil); embedding the champion/top-scorer
# teams is deferred until a consumer needs it (open/closed). Adds two derived
# fields the SPA uses to gate the prediction UI.
class TournamentBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :starts_at, :ends_at, :external_code,
         :champion_id, :runner_up_id, :third_place_id, :fourth_place_id, :top_scorer_id

  # Predictions lock one minute before the first kickoff (derived from the
  # fixture — see Tournament#predictions_lock_at), not at starts_at.
  field(:is_locked) { |tournament| tournament.predictions_locked? }

  # Countdown to the prediction deadline in seconds; clamped at 0 once locked
  # (0 too while the fixture is empty). Field name kept so the SPA needs no change.
  field(:seconds_until_kickoff) do |tournament|
    lock_at = tournament.predictions_lock_at
    lock_at ? [ (lock_at - Time.current).to_i, 0 ].max : 0
  end
end
