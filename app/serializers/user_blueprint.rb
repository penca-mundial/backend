# frozen_string_literal: true

# Minimal "current user" projection. Deliberately omits every credential-bearing
# column (encrypted_password, *_token, …) and the system flag — only fields the
# SPA actually renders are exposed here. Phase 9 will extend this with
# preferences if needed.
class UserBlueprint < Blueprinter::Base
  identifier :id

  fields :email, :username, :admin, :avatar_url, :timezone, :confirmed_at
end
