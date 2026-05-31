# frozen_string_literal: true

require "rails_helper"

# Scaffolding only — MatchScoringJob is a no-op until SCRUM-137 (Phase 5) fills
# in the real scoring logic. SyncMatch enqueues it on the finished transition.
RSpec.describe MatchScoringJob do
  it "is an ApplicationJob" do
    expect(described_class.ancestors).to include(ApplicationJob)
  end

  it "performs without raising (no-op for now)" do
    expect { described_class.perform_now(123) }.not_to raise_error
  end
end
