# frozen_string_literal: true

module Memberships
  # Raised when the general pool group has not been seeded.
  #
  # This deliberately inherits from Exception rather than StandardError. The
  # Service base class rescues every StandardError (including Penca::ServiceError)
  # and converts it into a failed ServiceResult, which would let
  # AddUserToGeneralPoolJob finish "successfully" and silently drop a user who
  # should have been enrolled. Living outside the StandardError tree lets this
  # error propagate through Service.call and the job, so SolidQueue records a
  # FailedExecution and the misconfigured environment is surfaced loudly.
  class GeneralPoolNotInitialized < Exception # rubocop:disable Lint/InheritException
  end
end
