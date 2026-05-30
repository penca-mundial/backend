# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memberships::AddToGeneralPool do
  let(:user) { create(:user) }

  context "with the general pool seeded" do
    let!(:pool) { create(:group, :general_pool) }

    it "creates the membership and succeeds" do
      result = described_class.call(user: user)

      expect(result).to be_success
      expect(result.data).to be_persisted
      expect(result.data.group).to eq(pool)
      expect(result.data.user).to eq(user)
    end

    it "is idempotent: returns the existing membership on a second call" do
      first  = described_class.call(user: user).data
      second = described_class.call(user: user).data

      expect(second).to eq(first)
      expect(pool.memberships.where(user_id: user.id).count).to eq(1)
    end
  end

  context "without a general pool" do
    # The error inherits from Exception (not StandardError), so it escapes the
    # Service base rescue and propagates to the caller instead of becoming a
    # failed ServiceResult. This is what makes the job fail loudly.
    it "raises GeneralPoolNotInitialized" do
      expect { described_class.call(user: user) }
        .to raise_error(Memberships::GeneralPoolNotInitialized, /general pool/i)
    end
  end
end
