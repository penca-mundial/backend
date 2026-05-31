# frozen_string_literal: true

module FootballData
  # Thin HTTP gateway around the football-data.org REST API (v4).
  #
  # This is the single place in the app allowed to perform outbound HTTP for
  # match data; business services (fixture sync, scoring) depend on it instead
  # of reaching for HTTParty themselves. It inherits from Service for the shared
  # logging helpers and project conventions, but exposes typed read methods
  # rather than a single #call.
  #
  # Two safeguards keep us within the 10 req/min free tier:
  #   * a rolling 60s request counter in Rails.cache that pauses once the limit
  #     is reached (see #throttle!);
  #   * a per-endpoint response cache (default 5 minutes, configurable per call
  #     via cache_ttl:; pass 0 to bypass it for live, fast-changing data) so
  #     repeat reads of the same data don't burn quota.
  class Client < Service
    DEFAULT_BASE_URL = "https://api.football-data.org/v4"
    WORLD_CUP_CODE = "WC"

    RATE_LIMIT_KEY = "football_data:requests"
    RATE_LIMIT = 10
    RATE_WINDOW = 60.seconds
    RESPONSE_TTL = 5.minutes

    # The sleeper is injected so specs can assert the rate limiter pauses
    # without actually blocking (see the architectural "dependency inversion"
    # convention). It defaults to Kernel#sleep bound to this instance.
    def initialize(sleeper: method(:sleep))
      @sleeper = sleeper
    end

    def competition(code = WORLD_CUP_CODE, cache_ttl: RESPONSE_TTL)
      get("/competitions/#{code}", cache_ttl: cache_ttl)
    end

    def competition_teams(code = WORLD_CUP_CODE, cache_ttl: RESPONSE_TTL)
      get("/competitions/#{code}/teams", cache_ttl: cache_ttl)
    end

    def competition_matches(code = WORLD_CUP_CODE, filters: {}, cache_ttl: RESPONSE_TTL)
      get("/competitions/#{code}/matches", query: filters, cache_ttl: cache_ttl)
    end

    def match(id, cache_ttl: RESPONSE_TTL)
      get("/matches/#{id}", cache_ttl: cache_ttl)
    end

    # Standings (group tables) for a competition. The code is a required
    # parameter — there is no default competition — so callers must pass the
    # tournament's own code and nothing is hardcoded to a single competition.
    def standings(code, cache_ttl: RESPONSE_TTL)
      get("/competitions/#{code}/standings", cache_ttl: cache_ttl)
    end

    private

    # Cached, rate-limited GET. A cache hit costs no quota; only a miss reaches
    # the network, and only after passing the rate limiter. Pass cache_ttl: 0 to
    # bypass the cache entirely (read-through every call) — used by live match
    # polling, which needs fresh scores and can't tolerate the default TTL.
    def get(path, query: {}, cache_ttl: RESPONSE_TTL)
      return fetch(path, query) if cache_ttl.zero?

      Rails.cache.fetch(cache_key(path, query), expires_in: cache_ttl) do
        fetch(path, query)
      end
    end

    # A single rate-limited network read (no caching).
    def fetch(path, query)
      throttle!
      request(path, query)
    end

    def request(path, query)
      response = HTTParty.get(
        "#{base_url}#{path}",
        headers: { "X-Auth-Token" => api_key.to_s, "Accept" => "application/json" },
        query: query
      )
      unless response.success?
        raise ApiError.new("football-data.org GET #{path} failed", status: response.code, body: response.body)
      end

      response.parsed_response
    end

    # Rolling-window limiter. #increment auto-initializes the key to 1 on the
    # first request of a window and the entry expires after RATE_WINDOW. Once the
    # window is saturated we pause until it rolls over, then drop the counter so
    # the waiting request opens a fresh window.
    def throttle!
      count = Rails.cache.increment(RATE_LIMIT_KEY, 1, expires_in: RATE_WINDOW)
      return if count.nil? || count <= RATE_LIMIT

      log_info("Rate limit reached (#{count} requests in #{RATE_WINDOW.to_i}s) — pausing")
      @sleeper.call(RATE_WINDOW.to_i)
      Rails.cache.delete(RATE_LIMIT_KEY)
    end

    def cache_key(path, query)
      [ "football_data", path, query.to_param ].join(":")
    end

    def base_url
      ENV.fetch("FOOTBALL_DATA_BASE_URL", DEFAULT_BASE_URL)
    end

    def api_key
      ENV["FOOTBALL_DATA_API_KEY"]
    end
  end
end
