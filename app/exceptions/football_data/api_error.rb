# frozen_string_literal: true

module FootballData
  # Raised when football-data.org returns a non-2xx response. Carries the HTTP
  # status and raw body so callers (and SolidQueue failed executions) can see
  # what the upstream API actually said.
  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      @status = status
      @body = body
      super(message || "football-data.org request failed (HTTP #{status})")
    end
  end
end
