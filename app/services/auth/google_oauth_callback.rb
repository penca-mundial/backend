# frozen_string_literal: true

module Auth
  # Resolves a Google OmniAuth callback to a User: re-uses the existing
  # OAuth-provisioned user when the (provider, uid) pair matches, surfaces a
  # `use_password` error when the email belongs to a password user (no silent
  # account merging), and otherwise creates a fresh user with no username
  # (the onboarding flow picks it later).
  class GoogleOauthCallback < Service
    PROVIDER = "google_oauth2"

    def initialize(auth_hash:)
      @auth_hash = auth_hash || {}
    end

    def call
      return reject("oauth_failure", :bad_request) if uid.blank? || email.blank?

      user = User.find_by(provider: PROVIDER, uid: uid)
      return reject("system_account", :forbidden) if user&.system?
      return success(user) if user

      existing = User.find_by(email: email)
      return reject("system_account", :forbidden) if existing&.system?
      return reject("use_password",   :conflict)  if existing && existing.provider.blank?

      success(create_oauth_user)
    end

    private

    def uid
      @uid ||= @auth_hash[:uid] || @auth_hash["uid"]
    end

    def info
      @info ||= @auth_hash[:info] || @auth_hash["info"] || {}
    end

    def email
      @email ||= (info[:email] || info["email"]).to_s.downcase.presence
    end

    def image
      info[:image] || info["image"]
    end

    def create_oauth_user
      # OAuth users never see the password — Devise just needs one that
      # satisfies our model validators (length + at least one digit). The
      # trailing "1" guarantees the digit no matter what friendly_token
      # produced.
      generated_password = "#{Devise.friendly_token(20)}1"

      User.create!(
        email:        email,
        provider:     PROVIDER,
        uid:          uid,
        avatar_url:   image,
        confirmed_at: Time.current,
        password:     generated_password
        # username intentionally nil — onboarding will set it
      )
    end

    def reject(code, status)
      ServiceResult.new(errors: [ code ], data: { code: code, status: status })
    end
  end
end
