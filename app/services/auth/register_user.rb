# frozen_string_literal: true

module Auth
  # Creates a new (unconfirmed) user. Devise's confirmable module enqueues the
  # confirmation email automatically; no session is created here — the user
  # must verify their email first.
  class RegisterUser < Service
    def initialize(email:, password:, username:)
      @email    = email
      @password = password
      @username = username
    end

    def call
      user = User.new(
        email:    @email,
        password: @password,
        username: @username
      )
      user.save!

      success(user)
    end
  end
end
