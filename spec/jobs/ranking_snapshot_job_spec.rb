# frozen_string_literal: true

require "rails_helper"

RSpec.describe RankingSnapshotJob do
  let(:tournament) { create(:tournament) } # the only tournament -> the "current" one
  let(:day) { Date.new(2026, 6, 15) }
  let(:day_iso) { day.iso8601 }
  # Pinned literal, NOT derived via the job's own expression (that would
  # self-mask a TZ-dependent bug in how the job computes the day start).
  let(:day_start) { Time.utc(2026, 6, 15) }

  def match_on(hours_into_day, status:)
    create(:match, tournament: tournament, status: status, kickoff_at: day_start + hours_into_day)
  end

  # A user with `points` match points in the tournament on the given day, via a
  # finished match (so it never counts as "pending").
  def scored_user(points)
    user = create(:user)
    prediction = create(:prediction, user: user, match: match_on(12.hours, status: "finished"))
    create(:prediction_score, prediction: prediction, points_result: points, multiplier: 1.0,
                              breakdown: { "result_rule" => "exact_score" })
    user
  end

  it "runs on the :default queue" do
    expect(described_class.queue_name).to eq("default")
  end

  it "does not capture while a match of the day is still scheduled/live" do
    match_on(10.hours, status: "finished")
    match_on(20.hours, status: "scheduled") # still pending

    described_class.perform_now(day_iso)

    expect(RankingSnapshot.count).to eq(0)
  end

  it "captures the GLOBAL snapshot (group_id NULL, tournament tagged, normalized snapshot_at)" do
    user = scored_user(10)

    described_class.perform_now(day_iso)

    row = RankingSnapshot.find_by(user_id: user.id)
    expect(row).to have_attributes(group_id: nil, tournament_id: tournament.id, points: 10)
    expect(row.snapshot_at).to eq(Time.utc(2026, 6, 15)) # normalized to UTC midnight
  end

  it "no-ops without error when there are no matches" do
    tournament # the current tournament exists, but no matches/users

    expect { described_class.perform_now(day_iso) }.not_to raise_error
    expect(RankingSnapshot.count).to eq(0)
  end

  it "no-ops without error when there is no current tournament" do
    expect { described_class.perform_now(day_iso) }.not_to raise_error
    expect(RankingSnapshot.count).to eq(0)
  end

  it "is idempotent for the same day: a second run does not duplicate" do
    scored_user(10)
    described_class.perform_now(day_iso)

    expect { described_class.perform_now(day_iso) }.not_to change(RankingSnapshot, :count)
  end

  it "defaults to today (UTC) when no date is given" do
    # A finished match today, nothing pending -> captures under today's UTC day.
    user = create(:user)
    today = Time.now.utc.to_date
    today_start_utc = Time.utc(today.year, today.month, today.day) # explicit UTC midnight, not the job's expression
    match = create(:match, tournament: tournament, status: "finished",
                           kickoff_at: today_start_utc + 12.hours)
    create(:prediction_score, prediction: create(:prediction, user: user, match: match),
                              points_result: 3, multiplier: 1.0, breakdown: { "result_rule" => "exact_score" })

    described_class.perform_now

    expect(RankingSnapshot.find_by(user_id: user.id).snapshot_at).to eq(today_start_utc)
  end
end
