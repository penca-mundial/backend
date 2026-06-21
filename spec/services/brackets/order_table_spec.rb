# frozen_string_literal: true

require "rails_helper"

RSpec.describe Brackets::OrderTable do
  subject(:table) do
    described_class.new(slots: [
      { "order" => 0, "sides" => [ { "group" => "A", "position" => 1 }, { "group" => "B", "position" => 2 } ] },
      { "order" => 1, "sides" => [ { "group" => "D", "position" => 1 }, { "position" => 3 } ] }
    ])
  end

  def meta(group, position) = { group: group, position: position }

  describe "#position_for" do
    it "matches a determinate slot regardless of side order" do
      expect(table.position_for(meta("A", 1), meta("B", 2))).to eq(0)
      expect(table.position_for(meta("B", 2), meta("A", 1))).to eq(0) # reversed
    end

    it "matches a 'vs best third' slot by the determinate side, any third group" do
      expect(table.position_for(meta("D", 1), meta("C", 3))).to eq(1)
      expect(table.position_for(meta("F", 3), meta("D", 1))).to eq(1) # a different third still fits
    end

    it "returns nil when the positions fit no slot (feed/standings disagreement)" do
      expect(table.position_for(meta("A", 1), meta("A", 2))).to be_nil # A2 is not B2
      expect(table.position_for(meta("D", 1), meta("C", 2))).to be_nil # C2 is not a third
    end

    it "exposes the curated orders" do
      expect(table.orders).to eq([ 0, 1 ])
    end
  end

  describe ".from_file" do
    it "returns nil for a competition with no curated table" do
      expect(described_class.from_file("NOPE")).to be_nil
      expect(described_class.from_file(nil)).to be_nil
    end
  end
end
