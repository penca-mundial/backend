# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrentTournamentQuery do
  describe ".call" do
    context "when a tournament is active" do
      it "returns the active one even when it is not the lowest id" do
        create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago)         # past (lower id)
        create(:tournament, starts_at: 1.week.from_now, ends_at: 1.month.from_now) # upcoming
        active = create(:tournament, starts_at: 1.day.ago, ends_at: 1.week.from_now) # active (higher id)

        expect(described_class.call).to eq(active)
      end

      it "returns the most recently started when several are active" do
        create(:tournament, starts_at: 5.days.ago, ends_at: 5.days.from_now)  # older start, lower id
        newer = create(:tournament, starts_at: 1.day.ago, ends_at: 5.days.from_now)

        expect(described_class.call).to eq(newer)
      end
    end

    context "when none are active but an upcoming exists" do
      it "returns the soonest-to-start, not the lowest id" do
        create(:tournament, starts_at: 1.month.ago, ends_at: 1.week.ago)            # past
        create(:tournament, starts_at: 10.days.from_now, ends_at: 40.days.from_now) # later upcoming, lower id
        soonest = create(:tournament, starts_at: 2.days.from_now, ends_at: 30.days.from_now)

        expect(described_class.call).to eq(soonest)
      end
    end

    context "when only past tournaments exist" do
      it "returns the most recently finished, not the lowest id" do
        create(:tournament, starts_at: 2.months.ago, ends_at: 1.month.ago) # older end, lower id
        recent = create(:tournament, starts_at: 3.weeks.ago, ends_at: 1.week.ago)

        expect(described_class.call).to eq(recent)
      end
    end

    context "when there are no tournaments" do
      it "returns nil" do
        expect(described_class.call).to be_nil
      end
    end
  end
end
