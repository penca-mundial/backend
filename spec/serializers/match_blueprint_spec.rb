# frozen_string_literal: true

require "rails_helper"

RSpec.describe MatchBlueprint do
  it "keeps the default fixture view free of the bracket topology fields" do
    hash = described_class.render_as_hash(create(:match, :knockout))

    expect(hash).not_to have_key(:feeds_into_match_id)
    expect(hash).not_to have_key(:feeds_into_slot)
    expect(hash).not_to have_key(:bracket_position)
  end

  it "exposes the topology passthrough fields under the :bracket view" do
    nxt = create(:match, :knockout)
    match = create(:match, :knockout, feeds_into: nxt, feeds_into_slot: "home", bracket_position: 3)

    hash = described_class.render_as_hash(match, view: :bracket)

    expect(hash).to include(feeds_into_match_id: nxt.id, feeds_into_slot: "home", bracket_position: 3)
    # the default fields and embedded teams are still present
    expect(hash).to include(:external_id, :status, :phase, :home_team, :away_team)
  end
end
