# frozen_string_literal: true

require "rails_helper"

RSpec.describe PhaseMultiplier, type: :model do
  it "has a valid factory" do
    expect(build(:phase_multiplier)).to be_valid
  end

  describe "phase enum" do
    it "uses the same phases as Match" do
      expect(described_class.phases.keys).to match_array(Match::PHASES)
    end

    it "rejects a value outside the closed set" do
      expect { build(:phase_multiplier, phase: "nonsense") }.to raise_error(ArgumentError)
    end
  end

  describe "validations" do
    it "rejects a non-positive multiplier" do
      expect(build(:phase_multiplier, multiplier: 0)).not_to be_valid
    end

    it "rejects a duplicate phase" do
      create(:phase_multiplier, phase: "group_stage")

      expect(build(:phase_multiplier, phase: "group_stage")).not_to be_valid
    end
  end

  describe ".for" do
    it "returns the multiplier as a Float" do
      create(:phase_multiplier, phase: "quarter_final", multiplier: 3.5)

      result = described_class.for(:quarter_final)

      expect(result).to eq(3.5)
      expect(result).to be_a(Float)
    end
  end
end
