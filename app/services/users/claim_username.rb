# frozen_string_literal: true

module Users
  # Set the username for an OAuth-provisioned user that has not picked one yet.
  # This is the "choose your handle" step right after a successful Google sign
  # in. Refuses to overwrite an existing username (returns a 409-shaped failure)
  # and surfaces model validation errors as a 422-shaped failure.
  class ClaimUsername < Service
    USERNAME_ALREADY_SET = {
      code:    "username_already_set",
      status:  :conflict,
      message: "Ya elegiste un nombre de usuario."
    }.freeze
    VALIDATION_ERROR = {
      code:   "validation_error",
      status: :unprocessable_content
    }.freeze

    def initialize(user:, username:)
      @user     = user
      @username = username
    end

    def call
      return reject(USERNAME_ALREADY_SET) if @user.username.present?

      @user.username = @username
      @user.save!
      success(@user)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.new(errors: e.record.errors.full_messages, data: VALIDATION_ERROR)
    end

    private

    def reject(reason)
      ServiceResult.new(
        errors: [ reason[:message] ],
        data:   reason.slice(:code, :status)
      )
    end
  end
end
