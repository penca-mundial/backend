# frozen_string_literal: true

# Minimal "current user" projection. Deliberately omits every credential-bearing
# column (encrypted_password, *_token, …) and the system flag — only fields the
# SPA actually renders are exposed here. Phase 9 will extend this with
# preferences if needed.
class UserBlueprint < Blueprinter::Base
  identifier :id

  # provider: "google_oauth2" for Google users, null for password users — lets
  # the SPA render the right "Cuenta" section per auth method.
  # created_at: account creation time ("Miembro desde", serialized ISO8601 like
  # the existing confirmed_at).
  fields :email, :username, :admin, :avatar_url, :timezone, :confirmed_at, :provider, :created_at
end
