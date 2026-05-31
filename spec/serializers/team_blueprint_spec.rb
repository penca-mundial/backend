# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeamBlueprint do
  let(:team) { create(:team, name: "Argentina", code3: "ARG", flag_url: "http://x/arg.png") }

  it "default view exposes the compact fields (same keys as the former team_hash)" do
    hash = described_class.render_as_hash(team)

    expect(hash.keys).to match_array(%i[id name code3 flag_url])
    expect(hash).to include(id: team.id, name: "Argentina", code3: "ARG", flag_url: "http://x/arg.png")
  end

  it "extended view adds external_id and tournament_id" do
    hash = described_class.render_as_hash(team, view: :extended)

    expect(hash.keys).to match_array(%i[id name code3 flag_url external_id tournament_id])
    expect(hash).to include(external_id: team.external_id, tournament_id: team.tournament_id)
  end
end
