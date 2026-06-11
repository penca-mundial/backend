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

  describe "minute" do
    it "populates the minute for a live match from the API" do
      match = create(:match, external_id: "min-1", status: "scheduled", kickoff_at: 1.hour.ago)
      stub_match("min-1", "status" => "IN_PLAY", "minute" => 67)

      described_class.call(match: match)

      expect(match.reload).to have_attributes(status: "live", minute: 67)
    end

    it "leaves the minute nil for a still-scheduled match" do
      match = create(:match, external_id: "min-2", status: "scheduled", kickoff_at: 2.hours.from_now)
      stub_match("min-2", "status" => "SCHEDULED")

      described_class.call(match: match)

      expect(match.reload.minute).to be_nil
    end

    it "stores a final minute stamped on the finished payload" do
      match = create(:match, external_id: "min-3", status: "live", kickoff_at: 1.hour.ago, minute: 88)
      stub_match("min-3", "status" => "FINISHED", "minute" => 90,
                          "score" => { "fullTime" => { "home" => 1, "away" => 0 } })

      described_class.call(match: match)

      expect(match.reload).to have_attributes(status: "finished", minute: 90)
    end

    it "keeps the last synced minute when a finished payload drops the field" do
      match = create(:match, external_id: "min-4", status: "live", kickoff_at: 1.hour.ago, minute: 90)
      stub_match("min-4", "status" => "FINISHED", "score" => { "fullTime" => { "home" => 2, "away" => 2 } })

      described_class.call(match: match)

      expect(match.reload).to have_attributes(status: "finished", minute: 90)
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

  describe "final -> finished triggers tournament scoring" do
    it "enqueues TournamentScoringJob (delayed) once when the FINAL finishes" do
      match = create(:match, :final, external_id: "fin-1", status: "live", kickoff_at: 1.hour.ago)
      stub_match("fin-1", "status" => "FINISHED",
                          "score" => { "fullTime" => { "home" => 2, "away" => 1 }, "winner" => "HOME_TEAM" })

      expect { described_class.call(match: match) }
        .to have_enqueued_job(TournamentScoringJob).with(match.tournament_id).exactly(:once)
    end

    it "still enqueues MatchScoringJob when the FINAL finishes" do
      match = create(:match, :final, external_id: "fin-2", status: "live", kickoff_at: 1.hour.ago)
      stub_match("fin-2", "status" => "FINISHED",
                          "score" => { "fullTime" => { "home" => 1, "away" => 0 }, "winner" => "HOME_TEAM" })

      expect { described_class.call(match: match) }
        .to have_enqueued_job(MatchScoringJob).with(match.id)
    end

    it "does not enqueue TournamentScoringJob when a non-final match finishes" do
      match = create(:match, :round_of_16, external_id: "fin-3", status: "live", kickoff_at: 1.hour.ago)
      stub_match("fin-3", "status" => "FINISHED",
                          "score" => { "fullTime" => { "home" => 1, "away" => 0 }, "winner" => "HOME_TEAM" })

      expect { described_class.call(match: match) }.not_to have_enqueued_job(TournamentScoringJob)
    end

    it "enqueues tournament scoring only on the transition, not on repeat runs" do
      match = create(:match, :final, external_id: "fin-4", status: "live", kickoff_at: 1.hour.ago)
      stub_match("fin-4", "status" => "FINISHED",
                          "score" => { "fullTime" => { "home" => 3, "away" => 2 }, "winner" => "HOME_TEAM" })

      expect { described_class.call(match: match) }.to have_enqueued_job(TournamentScoringJob).exactly(:once)

      clear_enqueued_jobs
      expect { described_class.call(match: match) }.not_to have_enqueued_job(TournamentScoringJob)
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

  describe "sync bookkeeping" do
    let(:match) { create(:match, external_id: "m-5", status: "scheduled", kickoff_at: 2.hours.from_now) }

    it "stamps last_synced_at so the polling cadence can be tracked" do
      stub_match("m-5", "status" => "SCHEDULED")

      expect { described_class.call(match: match) }
        .to change { match.reload.last_synced_at }.from(nil)
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

  describe "cache bypass" do
    let(:match)  { create(:match, external_id: "m-9", status: "scheduled", kickoff_at: 1.hour.from_now) }
    let(:client) { instance_double(FootballData::Client) }

    it "fetches the match read-through (cache_ttl: 0) so the live poll always hits the network" do
      allow(client).to receive(:match).and_return("status" => "IN_PLAY")

      described_class.call(match: match, client: client)

      expect(described_class::LIVE_CACHE_TTL).to eq(0)
      expect(client).to have_received(:match).with("m-9", cache_ttl: 0)
    end
  end

  describe "status regression guard" do
    it "keeps a live match live (and its score) when a stale scheduled payload arrives" do
      match = create(:match, external_id: "reg-1", status: "live", kickoff_at: 1.hour.ago,
                             home_score: 1, away_score: 0)
      stub_match("reg-1", "status" => "SCHEDULED")

      described_class.call(match: match)

      expect(match.reload).to have_attributes(status: "live", home_score: 1, away_score: 0)
    end

    it "keeps a finished match finished when a stale scheduled payload arrives" do
      match = create(:match, external_id: "reg-2", status: "finished", kickoff_at: 3.hours.ago,
                             home_score: 2, away_score: 1)
      stub_match("reg-2", "status" => "SCHEDULED")

      described_class.call(match: match)

      expect(match.reload).to have_attributes(status: "finished", home_score: 2, away_score: 1)
    end

    it "still applies a postponed payload over a live match (not a scheduled regression)" do
      match = create(:match, external_id: "reg-3", status: "live", kickoff_at: 1.hour.ago)
      stub_match("reg-3", "status" => "POSTPONED")

      described_class.call(match: match)

      expect(match.reload).to be_status_postponed
    end

    it "still applies a cancelled payload over a live match" do
      match = create(:match, external_id: "reg-4", status: "live", kickoff_at: 1.hour.ago)
      stub_match("reg-4", "status" => "CANCELLED")

      described_class.call(match: match)

      expect(match.reload).to be_status_cancelled
    end
  end

  describe "knockout result and advancing team" do
    it "stores the 90' result (regularTime), not the ET/penalty fullTime, with the advancing team" do
      match = create(:match, :round_of_16, external_id: "ko-1", status: "live", kickoff_at: 1.hour.ago)
      stub_match("ko-1", "status" => "FINISHED",
                         "score" => { "regularTime" => { "home" => 1, "away" => 1 },
                                      "fullTime" => { "home" => 7, "away" => 6 }, "winner" => "HOME_TEAM" })

      described_class.call(match: match)

      expect(match.reload).to have_attributes(home_score: 1, away_score: 1, advancing_team_id: match.home_team_id)
    end

    it "uses fullTime and maps AWAY_TEAM for a knockout settled in 90'" do
      match = create(:match, :round_of_16, external_id: "ko-2", status: "live", kickoff_at: 1.hour.ago)
      stub_match("ko-2", "status" => "FINISHED",
                         "score" => { "fullTime" => { "home" => 0, "away" => 2 }, "winner" => "AWAY_TEAM" })

      described_class.call(match: match)

      expect(match.reload).to have_attributes(home_score: 0, away_score: 2, advancing_team_id: match.away_team_id)
    end

    it "leaves advancing_team_id nil for a group-stage match" do
      match = create(:match, external_id: "grp-1", status: "live", kickoff_at: 1.hour.ago) # group_stage
      stub_match("grp-1", "status" => "FINISHED",
                          "score" => { "fullTime" => { "home" => 2, "away" => 1 }, "winner" => "HOME_TEAM" })

      described_class.call(match: match)

      expect(match.reload.advancing_team_id).to be_nil
    end

    it "leaves advancing_team_id nil (without raising) when a finished KO has no clear winner" do
      match = create(:match, :round_of_16, external_id: "ko-draw", status: "live", kickoff_at: 1.hour.ago)
      stub_match("ko-draw", "status" => "FINISHED",
                            "score" => { "fullTime" => { "home" => 1, "away" => 1 }, "winner" => "DRAW" })

      expect { described_class.call(match: match) }.not_to raise_error
      expect(match.reload.advancing_team_id).to be_nil
    end

    it "sets advancing_team_id before enqueuing the scoring job" do
      match = create(:match, :round_of_16, external_id: "ko-enq", status: "live", kickoff_at: 1.hour.ago)
      stub_match("ko-enq", "status" => "FINISHED",
                           "score" => { "fullTime" => { "home" => 1, "away" => 0 }, "winner" => "HOME_TEAM" })

      advancing_at_enqueue = nil
      allow(MatchScoringJob).to receive(:perform_later) do |id|
        advancing_at_enqueue = Match.find(id).advancing_team_id
      end

      described_class.call(match: match)

      expect(advancing_at_enqueue).to eq(match.home_team_id)
    end

    it "is idempotent: a re-sync keeps the same result and advancing team" do
      match = create(:match, :round_of_16, external_id: "ko-idem", status: "live", kickoff_at: 1.hour.ago)
      stub_match("ko-idem", "status" => "FINISHED",
                            "score" => { "regularTime" => { "home" => 2, "away" => 1 },
                                         "fullTime" => { "home" => 4, "away" => 3 }, "winner" => "HOME_TEAM" })

      described_class.call(match: match)
      first = match.reload.slice(:home_score, :away_score, :advancing_team_id)
      described_class.call(match: match)

      expect(match.reload.slice(:home_score, :away_score, :advancing_team_id)).to eq(first)
    end
  end
end
