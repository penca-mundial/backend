# Blueprinter serialization defaults: use the fast Oj generator and render all
# timestamps as ISO 8601 in UTC (the server always runs in UTC).
Blueprinter.configure do |config|
  config.generator = Oj
  config.datetime_format = ->(datetime) { datetime.utc.iso8601 }
end
