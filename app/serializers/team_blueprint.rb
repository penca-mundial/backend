# frozen_string_literal: true

# Canonical team projection, shared across the API (replaces the team_hash
# helper that was duplicated in MatchBlueprint and StandingBlueprint).
#
# - :default  — compact, for embedding inside other resources (matches,
#   standings): id, name, code3, flag_url. Same keys/values as the former
#   team_hash; key order is alphabetical (Blueprinter's global sort).
# - :extended — for the standalone teams endpoint: adds external_id,
#   tournament_id.
class TeamBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :code3, :flag_url

  view :extended do
    fields :external_id, :tournament_id
  end
end
