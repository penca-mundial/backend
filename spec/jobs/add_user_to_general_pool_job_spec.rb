# frozen_string_literal: true

require "rails_helper"

RSpec.describe AddUserToGeneralPoolJob do
  let(:user) { create(:user) }

  it "uses the :default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  context "with the general pool seeded" do
    let!(:pool) { create(:group, :general_pool) }

    it "adds the user as a member of the general pool" do
      expect do
        described_class.perform_now(user.id)
      end.to change { pool.memberships.where(user_id: user.id).count }.from(0).to(1)
    end

    it "is idempotent: a second run does not duplicate the membership" do
      described_class.perform_now(user.id)

      expect do
        described_class.perform_now(user.id)
      end.not_to change { pool.memberships.where(user_id: user.id).count }
    end

    it "delegates to Memberships::AddToGeneralPool" do
      expect(Memberships::AddToGeneralPool).to receive(:call).with(user: user).and_call_original

      described_class.perform_now(user.id)
    end
  end

  context "when the general pool has not been seeded" do
    # GeneralPoolNotInitialized is not a StandardError, so neither the Service
    # base nor ActiveJob swallows it: it propagates out of #perform. That is the
    # exact contract SolidQueue relies on — SolidQueue::ClaimedExecution#execute
    # rescues Exception and records a SolidQueue::FailedExecution for it (see
    # solid_queue gem). A swallowed error would instead let the job finish green.
    it "fails loudly so the job lands in SolidQueue::FailedExecution" do
      expect do
        described_class.perform_now(user.id)
      end.to raise_error(Memberships::GeneralPoolNotInitialized)
    end
  end
end
