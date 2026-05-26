# Value object returned by every Service. Wraps the produced data and any
# error messages, exposing a small success/failure interface.
class ServiceResult
  attr_reader :data, :errors

  def initialize(data: nil, errors: [])
    @data = data
    @errors = Array(errors)
  end

  def success?
    errors.empty?
  end

  def failure?
    !success?
  end

  # First error message, or nil when the result is successful.
  def error
    errors.first
  end
end
