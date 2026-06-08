require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # NOTE: Active Storage is currently UNUSED — no has_one_attached/has_many_attached
  # anywhere in app/, and user avatars are remote Google URLs, not uploads. Render's
  # disk is ephemeral, so if file uploads are ever added, switch this to a persistent
  # service (S3/R2) first.
  config.active_storage.service = :local

  # Requests that need to skip SSL redirect and host authorization: the health
  # check endpoints are probed over plain HTTP behind Render's proxy.
  health_check = ->(request) { request.path == "/up" || request.path == "/api/v1/health" }

  # Assume all access to the app is happening through a SSL-terminating reverse proxy
  # (Render terminates TLS and forwards X-Forwarded-Proto).
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the health check endpoints.
  config.ssl_options = { redirect: { exclude: health_check } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # Solid Cache lives in the primary database (single-database setup).
  config.cache_store = :solid_cache_store

  # Active Job uses Solid Queue (configured in config/application.rb), also in
  # the primary database — no separate queue database / connects_to.

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Transactional email through Resend (API key from RESEND_API_KEY).
  config.action_mailer.delivery_method = :resend

  # Set host to be used by links generated in mailer templates.
  #
  # Mail links must point at THIS service, not the SPA: Devise's confirmation
  # link hits /users/confirmation on the backend first (it confirms the user)
  # and only then redirects to FRONTEND_URL/confirm-email — same flow as
  # development, where the mailer host is localhost:3000. Render injects
  # RENDER_EXTERNAL_HOSTNAME (bare hostname, no scheme); the protocol is passed
  # separately, as url_for expects.
  config.action_mailer.default_url_options = {
    host: ENV.fetch("RENDER_EXTERNAL_HOSTNAME", "example.com"),
    protocol: "https"
  }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n. `true` would fall back to the DEFAULT
  # locale — which here is :es itself, so a key missing in es never reached the
  # :en texts and rendered the raw "Translation missing…" string (seen on the
  # pwned-password signup error). Fall back to :en explicitly, matching
  # config/application.rb.
  config.i18n.fallbacks = [ :en ]

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks. Rails
  # leaves host authorization OFF in production when config.hosts is empty, so
  # we only get protection by adding the real hostname. Render injects
  # RENDER_EXTERNAL_HOSTNAME automatically; when it is absent (e.g. a local
  # production-like boot) the list stays empty and authorization stays off.
  if ENV["RENDER_EXTERNAL_HOSTNAME"].present?
    config.hosts << ENV["RENDER_EXTERNAL_HOSTNAME"]

    # The custom domain(s) real traffic arrives through do NOT come in
    # RENDER_EXTERNAL_HOSTNAME — Render injects only its own *.onrender.com
    # hostname while preserving the original Host header. With authorization
    # active, a custom domain missing from this list would get 403 "Blocked
    # host" on ALL real traffic while the health check (excluded below) stayed
    # green — a silent outage. APP_CUSTOM_HOST is comma-separated to allow
    # more than one host.
    ENV.fetch("APP_CUSTOM_HOST", "").split(",").map(&:strip).reject(&:blank?).each do |host|
      config.hosts << host
    end

    # Skip DNS rebinding protection for the health check endpoints.
    config.host_authorization = { exclude: health_check }
  end
end
