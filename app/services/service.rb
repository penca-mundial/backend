# Base class for every service object. Subclasses implement an instance `#call`
# that returns a ServiceResult (use the `success`/`failure` helpers). Call a
# service through `SomeService.call(...)`, which instantiates it and runs `#call`,
# converting any raised exception into a failed ServiceResult.
class Service
  include ServiceLogger

  def self.call(*args, **kwargs, &block)
    service = new(*args, **kwargs, &block)
    service.call
  rescue Penca::ServiceError => e
    service&.log_error(e.message)
    ServiceResult.new(errors: [ e.message ])
  rescue ActiveRecord::RecordInvalid => e
    service&.log_error(e.message)
    ServiceResult.new(errors: e.record.errors.full_messages)
  rescue ActiveRecord::RecordNotSaved => e
    # A callback halting the save with `throw :abort` (e.g. a model guard) raises
    # this with a generic message; surface the record's own errors instead, like
    # the RecordInvalid sibling. Log the resolved message (not the generic
    # e.message) to match the siblings. presence || covers an :abort that left no
    # errors populated.
    messages = e.record&.errors&.full_messages.presence || [ e.message ]
    service&.log_error(messages.join("; "))
    ServiceResult.new(errors: messages)
  rescue ActiveRecord::RecordNotFound => e
    service&.log_error(e.message)
    ServiceResult.new(errors: [ I18n.t("services.errors.record_not_found", default: "Record not found") ])
  rescue StandardError => e
    service&.log_error("#{e.class}: #{e.message}")
    ServiceResult.new(errors: [ e.message ])
  end

  def call
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  private

  # Build a successful result wrapping the given data.
  def success(data = nil)
    ServiceResult.new(data:)
  end

  # Build a failed result from one or more error messages.
  def failure(errors)
    ServiceResult.new(errors:)
  end

  # Abort the service with a business-rule error.
  def raise_service_error(message)
    raise Penca::ServiceError, message
  end

  # Run a nested service result, raising (to abort this service) if it failed.
  # Returns the nested result's data on success.
  def invoke
    result = yield
    raise Penca::ServiceError, result.errors.to_sentence if result.failure?

    result.data
  end
end
