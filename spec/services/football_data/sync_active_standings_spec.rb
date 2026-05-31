# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::SyncActiveStandings do
  def base = "https://api.football-data.org/v4"
  def json_headers = { "Content-Type" => "application/json" }

  def stub_standings(code, body)
    stub_request(:get, "#{base}/competitions/#{code}/standings")
      .to_return(status: 200, body: body.to_json, headers: json_headers)
  end

  it "syncs standings only for active tournaments that have a competition code" do
    active = create(:tournament, :active, external_code: "WC")
    create(:team, tournament: active, external_id: "1")
    create(:team, tournament: active, external_id: "2")

    # Excluded: active but no code, and coded but not active (already ended).
    create(:tournament, :active, external_code: nil)
    create(:tournament, external_code: "CL", starts_at: 1.month.ago, ends_at: 1.day.ago)

    stub_standings("WC", {
      "standings" => [
        { "type" => "TOTAL", "group" => "GROUP_A",
          "table" => [
            { "position" => 1, "team" => { "id" => 1 }, "points" => 9 },
            { "position" => 2, "team" => { "id" => 2 }, "points" => 6 }
          ] }
      ]
    })

    result = described_class.call

    expect(result).to be_success
    expect(result.data).to eq(tournaments_synced: 1)
    expect(active.standings.count).to eq(2)
    # The other tournaments were skipped (no HTTP stub for CL was even needed).
    expect(Standing.where.not(tournament: active)).to be_empty
  end

  it "does not abort the batch when one tournament's sync fails" do
    ok = create(:tournament, :active, external_code: "WC")
    create(:team, tournament: ok, external_id: "1")
    failing = create(:tournament, :active, external_code: "CL")

    stub_standings("WC", {
      "standings" => [ { "type" => "TOTAL", "group" => "GROUP_A",
                         "table" => [ { "position" => 1, "team" => { "id" => 1 }, "points" => 9 } ] } ]
    })
    stub_request(:get, "#{base}/competitions/CL/standings").to_return(status: 500, body: "boom")

    result = described_class.call

    expect(result).to be_success
    expect(result.data).to eq(tournaments_synced: 2) # both attempted
    expect(ok.standings.count).to eq(1)              # the healthy one still synced
    expect(failing.standings).to be_empty
  end
end
