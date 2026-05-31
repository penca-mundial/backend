# frozen_string_literal: true

require "rails_helper"

RSpec.describe FootballData::GroupNormalizer do
  describe ".call" do
    it "strips the GROUP_ prefix" do
      expect(described_class.call("GROUP_A")).to eq("A")
    end

    it "strips a 'Group ' prefix with a space, case-insensitively" do
      expect(described_class.call("Group H")).to eq("H")
    end

    it "leaves a bare identifier untouched" do
      expect(described_class.call("A")).to eq("A")
    end

    it "does not constrain to A-L (multi-tournament group labels survive)" do
      expect(described_class.call("GROUP_M")).to eq("M")
      expect(described_class.call("GROUP_1")).to eq("1")
    end

    it "returns nil for blank or absent input" do
      expect(described_class.call(nil)).to be_nil
      expect(described_class.call("")).to be_nil
      expect(described_class.call("   ")).to be_nil
    end
  end
end
