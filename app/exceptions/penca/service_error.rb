module Penca
  # Raised inside a Service to signal a business-rule failure. The Service base
  # class rescues it and turns it into a failed ServiceResult.
  class ServiceError < StandardError
  end
end
