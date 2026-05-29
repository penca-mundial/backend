# frozen_string_literal: true

# Enqueued whenever a user becomes confirmed (email confirmation or Google
# signup). Adds them to the general pool group via Memberships::AddToGeneralPool.
class AddUserToGeneralPoolJob < ApplicationJob
  queue_as :default

  # If the user was deleted before the job ran, there is nothing to do.
  discard_on ActiveJob::DeserializationError

  def perform(user_id)
    user = User.find(user_id)
    Memberships::AddToGeneralPool.call(user: user)
  end
end
