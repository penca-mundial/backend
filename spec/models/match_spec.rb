# frozen_string_literal: true

require "rails_helper"

RSpec.describe Match, type: :model do
  it "has a valid factory" do
    expect(build(:match)).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:tournament) }
    it { is_expected.to belong_to(:home_team).class_name("Team") }
    it { is_expected.to belong_to(:away_team).class_name("Team") }
    it { is_expected.to belong_to(:advancing_team).class_name("Team").optional }
  end

  describe "status enum" do
    it "defines the expected statuses" do
      expect(described_class.statuses.keys)
        .to match_array(%w[scheduled live finished postponed cancelled])
    end

    it "exposes prefixed predicate methods" do
      expect(build(:match, :live)).to be_status_live
      expect(build(:match)).to be_status_scheduled
    end
  end

  describe "phase enum" do
    it "defines the expected phases" do
      expect(described_class.phases.keys).to match_array(
        %w[group_stage round_of_32 round_of_16 quarter_final semi_final third_place final]
      )
    end

    it "exposes prefixed predicate methods" do
      expect(build(:match, :knockout)).to be_phase_round_of_16
    end
  end

  describe "scopes" do
    it "filter matches by status" do
      scheduled = create(:match)
      live = create(:match, :live)
      finished = create(:match, :finished)

      expect(described_class.scheduled).to contain_exactly(scheduled)
      expect(described_class.live).to contain_exactly(live)
      expect(described_class.finished).to contain_exactly(finished)
    end
  end

  describe "validations" do
    it "is invalid with a negative home score" do
      expect(build(:match, home_score: -1)).not_to be_valid
    end

    it "is invalid with a negative away score" do
      expect(build(:match, away_score: -1)).not_to be_valid
    end

    it "rejects an advancing_team that did not play in the match" do
      match = create(:match, :knockout)
      outsider = create(:team, tournament: match.tournament)
      match.advancing_team = outsider

      expect(match).not_to be_valid
      expect(match.errors[:advancing_team_id]).to be_present
    end

    it "rejects an advancing_team during the group stage" do
      match = create(:match)
      match.advancing_team = match.home_team

      expect(match).not_to be_valid
      expect(match.errors[:advancing_team_id]).to be_present
    end

    it "accepts a participant advancing_team in a knockout phase" do
      match = create(:match, :knockout)
      match.advancing_team = match.away_team

      expect(match).to be_valid
    end
  end

  describe "the home/away team check constraint" do
    it "cannot be persisted with the same team as home and away" do
      team = create(:team)
      match = build(:match, tournament: team.tournament, home_team: team, away_team: team)

      expect { match.save! }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "#original_kickoff_at" do
    it "is set from kickoff_at on create" do
      kickoff = 3.days.from_now.change(usec: 0)
      match = create(:match, kickoff_at: kickoff)

      expect(match.original_kickoff_at).to be_within(1.second).of(kickoff)
    end
  end

  describe "bracket progression" do
    it "exposes the next-round match via #feeds_into" do
      final = create(:match, :final)
      semi  = create(:match, :semi_final,
                     tournament: final.tournament,
                     feeds_into: final, feeds_into_slot: "home")

      expect(semi.feeds_into).to eq(final)
    end

    it "exposes the feeder matches via #fed_by" do
      final  = create(:match, :final)
      semi_a = create(:match, :semi_final,
                      tournament: final.tournament,
                      feeds_into: final, feeds_into_slot: "home")
      semi_b = create(:match, :semi_final,
                      tournament: final.tournament,
                      feeds_into: final, feeds_into_slot: "away")

      expect(final.fed_by).to contain_exactly(semi_a, semi_b)
    end

    it "rejects a final match that has feeds_into set" do
      next_round = create(:match, :semi_final)
      bad_final  = build(:match, :final,
                         tournament: next_round.tournament,
                         feeds_into: next_round, feeds_into_slot: "home")

      expect(bad_final).not_to be_valid
      expect(bad_final.errors[:feeds_into_match_id]).to be_present
    end

    it "rejects feeds_into without feeds_into_slot" do
      final = create(:match, :final)
      semi  = build(:match, :semi_final,
                    tournament: final.tournament, feeds_into: final)

      expect(semi).not_to be_valid
      expect(semi.errors[:feeds_into_slot]).to be_present
    end

    it "is valid when both feeds_into and feeds_into_slot are set" do
      final = create(:match, :final)
      semi  = build(:match, :semi_final,
                    tournament: final.tournament,
                    feeds_into: final, feeds_into_slot: "home")

      expect(semi).to be_valid
    end

    it "preloads the self-referential association without N+1" do
      tournament = create(:tournament)
      final = create(:match, :final, tournament: tournament)
      2.times do |i|
        create(:match, :semi_final,
               tournament: tournament,
               feeds_into: final,
               feeds_into_slot: i.zero? ? "home" : "away")
      end

      query_count = 0
      counter = lambda do |_name, _started, _finished, _id, payload|
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.where(tournament: tournament).includes(:feeds_into).each(&:feeds_into)
      end

      # 1 query loads matches + 1 preloads feeds_into → 2 total, regardless of N.
      expect(query_count).to be <= 2
    end
  end

  describe "prediction-lock scheduling" do
    include ActiveJob::TestHelper

    it "schedules a MatchLockJob a minute before kickoff on create" do
      kickoff = 2.days.from_now.change(usec: 0)

      expect { create(:match, kickoff_at: kickoff) }
        .to have_enqueued_job(MatchLockJob).at(kickoff - 1.minute)
    end

    it "does not schedule a lock job for a match created already finished" do
      expect { create(:match, :finished) }.not_to have_enqueued_job(MatchLockJob)
    end

    it "reschedules when a scheduled match's kickoff moves" do
      match = create(:match, kickoff_at: 2.days.from_now)
      clear_enqueued_jobs
      new_kickoff = 4.days.from_now.change(usec: 0)

      expect { match.update!(kickoff_at: new_kickoff) }
        .to have_enqueued_job(MatchLockJob).at(new_kickoff - 1.minute)
    end

    it "does not reschedule on an unrelated update" do
      match = create(:match)
      clear_enqueued_jobs

      expect { match.update!(home_score: 3) }.not_to have_enqueued_job(MatchLockJob)
    end
  end
end
