# frozen_string_literal: true

# Accepts lowercase ASCII letters, digits and underscores, 3 to 20 chars.
# Records that pre-normalize the value (e.g. User downcasing usernames) get a
# meaningful "lowercase only" enforcement out of this regex too.
class UsernameFormatValidator < ActiveModel::EachValidator
  FORMAT = /\A[a-z0-9_]{3,20}\z/

  def validate_each(record, attribute, value)
    return if value.blank?
    return if value.match?(FORMAT)

    record.errors.add(attribute, :invalid)
  end
end
