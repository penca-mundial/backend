# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/initializers/required_env" do # rubocop:disable RSpec/DescribeClass
  let(:initializer_path) { Rails.root.join("config/initializers/required_env.rb") }
  let(:required_keys) do
    %w[CORS_ORIGINS FOOTBALL_DATA_API_KEY GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET FRONTEND_URL]
  end

  def load_initializer
    load initializer_path
  end

  # Examples mutate ENV; snapshot the touched keys and restore them afterwards
  # so the rest of the suite sees the original environment.
  around do |example|
    previous = required_keys.index_with { |key| ENV[key] }
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  context "when not in production" do
    it "does not raise even when every required variable is missing" do
      required_keys.each { |key| ENV.delete(key) }

      expect { load_initializer }.not_to raise_error
    end
  end

  context "when in production" do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      required_keys.each { |key| ENV[key] = "value" }
    end

    it "boots cleanly when every required variable is set" do
      expect { load_initializer }.not_to raise_error
    end

    it "raises naming every missing variable" do
      ENV.delete("CORS_ORIGINS")
      ENV.delete("GOOGLE_CLIENT_ID")

      expect { load_initializer }.to raise_error(RuntimeError) do |error|
        expect(error.message).to include("CORS_ORIGINS", "GOOGLE_CLIENT_ID")
        expect(error.message).not_to include("FOOTBALL_DATA_API_KEY")
      end
    end

    it "treats blank values as missing" do
      ENV["FOOTBALL_DATA_API_KEY"] = "   "

      expect { load_initializer }.to raise_error(RuntimeError, /FOOTBALL_DATA_API_KEY/)
    end
  end
end
