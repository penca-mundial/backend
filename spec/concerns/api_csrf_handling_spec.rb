# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiCsrfHandling do
  def callback_filters(klass)
    klass._process_action_callbacks.map(&:filter)
  end

  # A controller that ships Rails' default HTML-form forgery protection, i.e.
  # the `verify_authenticity_token` before_action is registered.
  let(:protected_class) do
    Class.new(ActionController::Base) do
      protect_from_forgery with: :exception

      def self.name = "ProtectedDummyController"
    end
  end

  it "leaves verify_authenticity_token registered on a plain protected controller" do
    expect(callback_filters(protected_class)).to include(:verify_authenticity_token)
  end

  it "skips verify_authenticity_token when the concern is included" do
    api_class = Class.new(protected_class) do
      include ApiCsrfHandling

      def self.name = "ApiDummyController"
    end

    expect(callback_filters(api_class)).not_to include(:verify_authenticity_token)
  end

  it "is safe to include in an API-only controller that never registered forgery protection" do
    expect do
      Class.new(ActionController::API) do
        include ApiCsrfHandling

        def self.name = "ApiOnlyDummyController"
      end
    end.not_to raise_error
  end
end
