# Resend transactional email. The API key is only needed in production (the
# :resend delivery method); a missing key here does not break boot — development
# delivers via Mailcatcher (SMTP) and test uses the :test adapter.
Resend.api_key = ENV["RESEND_API_KEY"]
