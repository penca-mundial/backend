# Base class for query objects, which encapsulate a single read of the database
# and return a relation or scalar. Subclasses implement `#call`. Invoke through
# `SomeQuery.call(...)`.
class ApplicationQuery
  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs, &block).call
  end

  # Optionally seed the query with a starting relation.
  def initialize(relation = nil)
    @relation = relation
  end

  def call
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  private

  attr_reader :relation
end
