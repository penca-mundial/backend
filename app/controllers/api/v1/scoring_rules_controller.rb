# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/scoring_rules — the full scoring configuration (per-match and
    # special rule points + per-phase multipliers) for the public rules page.
    # Public, like the other read endpoints, and read straight from the
    # admin-editable models via ScoringConfigQuery.
    #
    # Cached with a short TTL (rather than invalidating when an admin edits a
    # value): the config changes rarely and ~30s of staleness is irrelevant,
    # while the TTL dedupes the SPA's polling — same pattern as the standings
    # endpoints.
    class ScoringRulesController < BaseController
      skip_before_action :require_user!

      CACHE_TTL = 30.seconds

      def index
        body = Rails.cache.fetch("scoring_config", expires_in: CACHE_TTL) do
          config = ScoringConfigQuery.call
          {
            scoring_rules:     ScoringRuleBlueprint.render_as_hash(config.scoring_rules),
            phase_multipliers: PhaseMultiplierBlueprint.render_as_hash(config.phase_multipliers)
          }.to_json
        end
        render body: body, content_type: "application/json"
      end
    end
  end
end
