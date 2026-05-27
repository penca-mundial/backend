# HTTP-layer rate limiting and abuse protection.
#
# Throttle counters are stored in Rails.cache (Solid Cache, backed by the
# primary Postgres database). All paths are under the /api/v1 namespace.
Rack::Attack.cache.store = Rails.cache

module RackAttackRequest
  module_function

  API_PREFIX = "/api/v1"

  def api_path?(req, path)
    req.path == "#{API_PREFIX}#{path}"
  end

  # Pull the email out of a JSON (or form) login body without consuming the
  # stream for the downstream app.
  def login_email(req)
    raw = req.body.read
    req.body.rewind
    email = if raw.present?
      begin
        JSON.parse(raw)["email"]
      rescue JSON::ParserError
        req.params["email"]
      end
    else
      req.params["email"]
    end
    email.to_s.downcase.presence
  end

  # Best-effort current user id (Warden). Falls back to the IP when there is no
  # authenticated user, so the throttle still applies.
  def user_or_ip(req)
    req.env["warden"]&.user&.id || req.ip
  rescue StandardError
    req.ip
  end
end

# Brute-force protection on login: 5 attempts / 5 min per IP + email.
Rack::Attack.throttle("auth/login", limit: 5, period: 5.minutes) do |req|
  if req.post? && RackAttackRequest.api_path?(req, "/auth/login")
    email = RackAttackRequest.login_email(req)
    "#{req.ip}:#{email}" if email
  end
end

# Signup spam: 3 / hour per IP.
Rack::Attack.throttle("auth/signup", limit: 3, period: 1.hour) do |req|
  req.ip if req.post? && RackAttackRequest.api_path?(req, "/auth/signup")
end

# Password reset abuse: 3 / hour per IP.
Rack::Attack.throttle("auth/password", limit: 3, period: 1.hour) do |req|
  req.ip if req.post? && RackAttackRequest.api_path?(req, "/auth/password")
end

# Confirmation resend abuse: 3 / hour per IP.
Rack::Attack.throttle("auth/confirmation", limit: 3, period: 1.hour) do |req|
  req.ip if req.post? && RackAttackRequest.api_path?(req, "/auth/confirmation")
end

# Prediction writes: 60 / min per user (falls back to IP).
Rack::Attack.throttle("predictions", limit: 60, period: 1.minute) do |req|
  RackAttackRequest.user_or_ip(req) if req.put? && RackAttackRequest.api_path?(req, "/predictions")
end

# Generic safety net: 300 requests / 5 min per IP across the API.
Rack::Attack.throttle("api/ip", limit: 300, period: 5.minutes) do |req|
  req.ip if req.path.start_with?(RackAttackRequest::API_PREFIX)
end

# Block obviously scripted abuse: no User-Agent on auth endpoints.
Rack::Attack.blocklist("auth/missing-user-agent") do |req|
  req.path.start_with?("#{RackAttackRequest::API_PREFIX}/auth") && req.user_agent.blank?
end

# Throttled requests get a 429 with Retry-After and a JSON error body.
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  retry_after = (match_data[:period] || 60).to_i

  headers = {
    "Content-Type" => "application/json",
    "Retry-After" => retry_after.to_s
  }
  body = {
    error: {
      code: "rate_limited",
      message: "Demasiadas solicitudes. Esperá un momento e intentá de nuevo."
    }
  }.to_json

  [ 429, headers, [ body ] ]
end
