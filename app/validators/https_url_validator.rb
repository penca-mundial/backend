# frozen_string_literal: true

# Accepts only well-formed https URLs (scheme https + a host). Blank values are
# skipped — pair with `allow_blank: true` when the attribute is optional. Domain
# is intentionally NOT restricted (Google and Cloudinary avatars must both pass).
class HttpsUrlValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    uri = URI.parse(value)
    return if uri.is_a?(URI::HTTPS) && uri.host.present?

    record.errors.add(attribute, :insecure_url)
  rescue URI::InvalidURIError
    record.errors.add(attribute, :insecure_url)
  end
end
