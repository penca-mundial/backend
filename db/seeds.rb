# frozen_string_literal: true

# Idempotent baseline data needed to run the app on a fresh DB. The order is
# load-bearing: teams need the tournament; the general pool needs the system
# user. Every step uses find_or_create_by! so re-running is a no-op.
require_relative "seeds/system_user"
require_relative "seeds/tournament"
require_relative "seeds/teams"
require_relative "seeds/scoring_rules"
require_relative "seeds/phase_multipliers"
require_relative "seeds/general_pool"

Seeds::SystemUser.call
Seeds::Tournament.call
Seeds::Teams.call
Seeds::ScoringRules.call
Seeds::PhaseMultipliers.call
Seeds::GeneralPool.call
