# frozen_string_literal: true

# Rejects values that are not strictly in the future (past or "now" both fail).
# Accepts Date, Time, DateTime, and ActiveSupport::TimeWithZone via the shared
# `future?` extension. Blank values are skipped — pair with `presence: true`
# when the attribute is required.
class FutureDateValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    return if value.future?

    record.errors.add(attribute, :not_in_future)
  end
end
