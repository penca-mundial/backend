# frozen_string_literal: true

require "rails_helper"
require "digest"

RSpec.describe "POST /api/v1/auth/signup", type: :request do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:valid_params) do
    { email: "alice@example.com", password: "Sup3rSecret9", username: "alice_99" }
  end

  # Rack::Attack blocks blank User-Agent on /auth/* — always send one.
  let(:headers) { { "User-Agent" => "rspec" } }

  describe "with valid params" do
    it "creates an unconfirmed user and returns 201 with the user payload" do
      expect do
        post "/api/v1/auth/signup", params: valid_params, headers: headers
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["user"]).to include(
        "email"        => "alice@example.com",
        "username"     => "alice_99",
        "confirmed_at" => nil
      )
      expect(body["user"]).not_to have_key("encrypted_password")
      expect(body["user"]).not_to have_key("confirmation_token")
      expect(body["user"]).not_to have_key("reset_password_token")

      expect(User.find_by!(email: "alice@example.com").confirmed_at).to be_nil
    end

    it "enqueues the confirmation email asynchronously (deliver_later, not sync)" do
      expect do
        post "/api/v1/auth/signup", params: valid_params, headers: headers
      end.to have_enqueued_mail(Devise::Mailer, :confirmation_instructions)

      # Nothing was delivered synchronously inside the request.
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "delivers the confirmation to the new user when the job runs" do
      perform_enqueued_jobs do
        post "/api/v1/auth/signup", params: valid_params, headers: headers
      end

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "alice@example.com" ])
      expect(mail.subject).to match(/confirma|confirmation/i)
    end

    it "isolates a delivery failure from the signup — no rollback, no blocked user, no raw error" do
      # The signup commits and returns BEFORE the deferred mail job runs, so the
      # request is clean regardless of the provider.
      expect do
        post "/api/v1/auth/signup", params: valid_params, headers: headers
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.body).not_to include("Resend")
      user = User.find_by!(email: "alice@example.com")

      # Now the queued job fails at delivery time (as Resend would on an
      # unverified domain). The already-persisted signup is untouched.
      allow(Devise::Mailer).to receive(:confirmation_instructions)
        .and_raise(StandardError, "Resend: domain not verified")
      expect { perform_enqueued_jobs }.to raise_error(/Resend/)
      expect(User.exists?(user.id)).to be(true)
    end

    it "does not create a session (the user must confirm their email first)" do
      post "/api/v1/auth/signup", params: valid_params, headers: headers

      # No Set-Cookie that names the session, since signup does not sign in.
      session_cookies = response.headers["Set-Cookie"].to_s
      expect(session_cookies).not_to include("_penca_session")
    end
  end

  # Regression: the test env disables forgery protection
  # (config.action_controller.allow_forgery_protection = false), which hid a
  # 500 that only fired in development/production. The previous
  # `protect_from_forgery with: :null_session` setup crashed on every tokenless
  # POST because ActionController::API has no Flash middleware and
  # `request.flash=` is undefined. Flip the flag on so this exercises dev parity.
  describe "with forgery protection enabled (dev/prod parity)" do
    around do |example|
      original = Api::V1::BaseController.allow_forgery_protection
      Api::V1::BaseController.allow_forgery_protection = true
      example.run
      Api::V1::BaseController.allow_forgery_protection = original
    end

    it "creates the user without an authenticity_token instead of raising" do
      expect do
        post "/api/v1/auth/signup", params: valid_params, headers: headers
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["user"]).to include("email" => "alice@example.com")
    end
  end

  describe "with a duplicate email" do
    it "returns 422 with the Spanish taken message" do
      create(:user, email: "alice@example.com")

      post "/api/v1/auth/signup", params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
      expect(response.parsed_body.dig("error", "details", "errors")).to include("Email ya está en uso")
    end
  end

  describe "with a duplicate username" do
    it "returns 422 with the Spanish taken message" do
      create(:user, username: "alice_99")

      post "/api/v1/auth/signup", params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "errors")).to include("Nombre de usuario ya está en uso")
    end
  end

  describe "with a too-short password" do
    it "returns 422 with the Spanish length message in Spanish (no English fallback)" do
      post "/api/v1/auth/signup",
           params: valid_params.merge(password: "Ab3"),
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      errors = response.parsed_body.dig("error", "details", "errors")
      expect(errors.join).to include("Contraseña es demasiado corto")
      expect(errors.join).not_to match(/is too short|can't be blank|has already/)
    end
  end

  describe "with a password missing a digit" do
    it "returns 422 with the Spanish attribute and message" do
      post "/api/v1/auth/signup",
           params: valid_params.merge(password: "SupersecretNoDigit"),
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "errors"))
        .to include("Contraseña debe contener al menos un número")
    end
  end

  describe "with a pwned password" do
    # Override the global "not found" HIBP stub for this password so the
    # devise-pwned_password validator rejects it.
    before do
      sha1   = Digest::SHA1.hexdigest(valid_params[:password]).upcase
      prefix = sha1[0...5]
      suffix = sha1[5..]
      stub_request(:get, "https://api.pwnedpasswords.com/range/#{prefix}")
        .to_return(status: 200, body: "#{suffix}:42\r\n")
    end

    it "returns 422 with the Spanish pwned message (no raw i18n fallback)" do
      post "/api/v1/auth/signup", params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "errors")).to include(
        "Contraseña apareció en filtraciones de datos conocidas. Elegí una contraseña distinta."
      )
      expect(response.parsed_body.dig("error", "details", "errors").join).not_to include("Translation missing")
    end
  end
end
