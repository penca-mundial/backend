# frozen_string_literal: true

require "rails_helper"

RSpec.describe Matches::ScheduleLockJob do
  include ActiveJob::TestHelper

  let(:kickoff) { 3.days.from_now.change(usec: 0) }
  let(:match)   { create(:match, kickoff_at: kickoff) }

  describe "scheduling" do
    it "enqueues MatchLockJob for the match a minute before kickoff" do
      clear_enqueued_jobs # drop the job enqueued by the create callback

      expect { described_class.call(match: match) }
        .to have_enqueued_job(MatchLockJob).with(match.id).at(kickoff - 1.minute)
    end

    it "returns a successful result" do
      expect(described_class.call(match: match)).to be_success
    end
  end

  describe "cancelling the previous lock job" do
    # Lock jobs live as SolidQueue::Job rows in production; build them directly
    # here so the cancellation logic can be tested without a running worker.
    def schedule_row(match_id)
      SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "MatchLockJob",
        active_job_id: SecureRandom.uuid,
        arguments: { "job_class" => "MatchLockJob", "arguments" => [ match_id ] }.to_json,
        scheduled_at: kickoff - 1.minute
      )
    end

    it "destroys the pending lock job for the same match" do
      row = schedule_row(match.id)

      expect { described_class.call(match: match) }
        .to change { SolidQueue::Job.exists?(row.id) }.from(true).to(false)
    end

    it "leaves lock jobs belonging to other matches alone" do
      other = schedule_row(match.id + 1)

      described_class.call(match: match)

      expect(SolidQueue::Job.exists?(other.id)).to be(true)
    end
  end
end
