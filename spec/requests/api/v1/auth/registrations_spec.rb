# frozen_string_literal: true

require "rails_helper"
require "digest"

RSpec.describe "POST /api/v1/auth/signup", type: :request do # rubocop:disable RSpec/DescribeClass
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

    it "sends the confirmation email to the new user" do
      expect do
        post "/api/v1/auth/signup", params: valid_params, headers: headers
      end.to change { ActionMailer::Base.deliveries.size }.by(1)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "alice@example.com" ])
      expect(mail.subject).to match(/confirma|confirmation/i)
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
    it "returns 422 with a validation error" do
      create(:user, email: "alice@example.com")

      post "/api/v1/auth/signup", params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("validation_error")
      expect(response.parsed_body.dig("error", "details", "errors").join).to match(/[Ee]mail/)
    end
  end

  describe "with a duplicate username" do
    it "returns 422 with a validation error" do
      create(:user, username: "alice_99")

      post "/api/v1/auth/signup", params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "errors").join).to match(/[Uu]sername/)
    end
  end

  describe "with a password missing a digit" do
    it "returns 422 with a validation error" do
      post "/api/v1/auth/signup",
           params: valid_params.merge(password: "SupersecretNoDigit"),
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "errors").join).to match(/[Pp]assword/)
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

    it "returns 422 with a validation error" do
      post "/api/v1/auth/signup", params: valid_params, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details", "errors").join).to match(/[Pp]assword/)
    end
  end
end
