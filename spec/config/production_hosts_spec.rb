# frozen_string_literal: true

require "rails_helper"

# Loads the REAL config/environments/production.rb against a stubbed
# Rails.application whose `config` is a permissive double — except `hosts`,
# which is a real array — so the host-authorization wiring can be asserted
# without booting a production app.
RSpec.describe "config/environments/production host authorization" do # rubocop:disable RSpec/DescribeClass
  let(:env_keys) { %w[RENDER_EXTERNAL_HOSTNAME APP_CUSTOM_HOST FRONTEND_URL RAILS_LOG_LEVEL] }
  let(:hosts) { [] }
  let(:config) do
    double("config").as_null_object.tap do |c| # rubocop:disable RSpec/VerifiedDoubles
      allow(c).to receive(:hosts).and_return(hosts)
    end
  end

  around do |example|
    previous = env_keys.index_with { |key| ENV[key] }
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def load_production_env
    # Capture the real root BEFORE stubbing Rails.application: Rails.root reads
    # application.config.root, and lazy requires fired while the file loads
    # (bootsnap's load-path cache, autoloaded ActiveSupport constants) need it.
    root = Rails.root

    context = Struct.new(:config).new(config)
    application = double("application") # rubocop:disable RSpec/VerifiedDoubles
    allow(application).to receive(:configure) { |&block| context.instance_eval(&block) }
    allow(application).to receive(:config).and_return(double("app_config", root: root)) # rubocop:disable RSpec/VerifiedDoubles
    allow(Rails).to receive(:application).and_return(application)

    load root.join("config/environments/production.rb")
  end

  context "with APP_CUSTOM_HOST set" do
    it "allows the custom domain(s) alongside the Render hostname" do
      ENV["RENDER_EXTERNAL_HOSTNAME"] = "penca-backend.onrender.com"
      ENV["APP_CUSTOM_HOST"] = "api.example.app, www.api.example.app"

      load_production_env

      expect(hosts).to contain_exactly(
        "penca-backend.onrender.com", "api.example.app", "www.api.example.app"
      )
      expect(config).to have_received(:host_authorization=)
    end

    it "ignores blank entries in the comma-separated list" do
      ENV["RENDER_EXTERNAL_HOSTNAME"] = "penca-backend.onrender.com"
      ENV["APP_CUSTOM_HOST"] = " ,api.example.app,, "

      load_production_env

      expect(hosts).to contain_exactly("penca-backend.onrender.com", "api.example.app")
    end
  end

  context "without APP_CUSTOM_HOST" do
    it "keeps the previous behavior: only the Render hostname is allowed" do
      ENV["RENDER_EXTERNAL_HOSTNAME"] = "penca-backend.onrender.com"
      ENV.delete("APP_CUSTOM_HOST")

      load_production_env

      expect(hosts).to contain_exactly("penca-backend.onrender.com")
      expect(config).to have_received(:host_authorization=)
    end

    it "leaves host authorization off when RENDER_EXTERNAL_HOSTNAME is absent" do
      ENV.delete("RENDER_EXTERNAL_HOSTNAME")
      ENV["APP_CUSTOM_HOST"] = "api.example.app" # guarded by the Render env

      load_production_env

      expect(hosts).to be_empty
      expect(config).not_to have_received(:host_authorization=)
    end
  end
end
