# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::SyncMatch do
  include ActiveJob::TestHelper

  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  def stub_match(external_id, body)
    stub_request(:get, "#{base}/matches/#{external_id}")
      .to_return(status: 200, body: body.to_json, headers: json_headers)
  end

  describe "scheduled -> live" do
    let(:match) { create(:match, external_id: "m-1", status: "scheduled", kickoff_at: 2.hours.from_now) }

    it "updates the status to live and enqueues no scoring job" do
      stub_match("m-1", "status" => "IN_PLAY", "score" => { "fullTime" => { "home" => 0, "away" => 0 } })

      expect { described_class.call(match: match) }.not_to have_enqueued_job(MatchScoringJob)
      expect(match.reload).to be_status_live
    end
  end

  describe "-> finished" do
    let(:match) { create(:match, external_id: "m-2", status: "live", kickoff_at: 1.hour.ago) }

    it "stores the final score, marks it finished and enqueues MatchScoringJob" do
      stub_match("m-2",
                 "status" => "FINISHED",
                 "score" => { "fullTime" => { "home" => 2, "away" => 1 } },
                 "goals" => [ { "minute" => 23, "scorer" => { "name" => "Messi" } } ])

      expect { described_class.call(match: match) }
        .to have_enqueued_job(MatchScoringJob).with(match.id)

      match.reload
      expect(match).to be_status_finished
      expect(match.home_score).to eq(2)
      expect(match.away_score).to eq(1)
      expect(match.events_log.first).to include("minute" => 23)
    end
  end

  describe "kickoff change while scheduled" do
    let(:match) { create(:match, external_id: "m-3", status: "scheduled", kickoff_at: 2.days.from_now) }
    let(:new_kickoff) { 5.days.from_now.change(usec: 0) }

    it "reschedules the lock job for the new kickoff" do
      stub_match("m-3", "status" => "SCHEDULED", "utcDate" => new_kickoff.utc.iso8601)
      clear_enqueued_jobs # drop the create-time lock job

      expect { described_class.call(match: match) }
        .to have_enqueued_job(MatchLockJob).at(new_kickoff - 1.minute)
      expect(match.reload.kickoff_at).to eq(new_kickoff)
    end
  end

  describe "idempotency" do
    let(:match) { create(:match, external_id: "m-4", status: "live", kickoff_at: 1.hour.ago) }

    it "enqueues the scoring job only on the transition, not on repeat runs" do
      stub_match("m-4", "status" => "FINISHED", "score" => { "fullTime" => { "home" => 1, "away" => 0 } })

      expect { described_class.call(match: match) }.to have_enqueued_job(MatchScoringJob).exactly(:once)

      clear_enqueued_jobs
      expect { described_class.call(match: match) }.not_to have_enqueued_job(MatchScoringJob)
    end
  end
end
