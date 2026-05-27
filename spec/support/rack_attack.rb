# Rack::Attack test setup. Throttling is disabled by default so it doesn't
# interfere with unrelated specs; enable it per-example with `rack_attack: true`.
# Counters use an in-memory store that is cleared before each throttling spec.
RSpec.configure do |config|
  config.before(:suite) do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  config.before do
    Rack::Attack.enabled = false
  end

  config.before(:each, :rack_attack) do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end
end
