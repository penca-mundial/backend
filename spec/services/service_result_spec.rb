require "rails_helper"

RSpec.describe ServiceResult do
  context "with a successful result" do
    subject(:result) { described_class.new(data: { id: 1 }) }

    it { expect(result).to be_success }
    it { expect(result).not_to be_failure }

    it "exposes the data and no errors" do
      expect(result.data).to eq(id: 1)
      expect(result.errors).to eq([])
      expect(result.error).to be_nil
    end
  end

  context "with a failed result" do
    subject(:result) { described_class.new(errors: [ "boom", "bang" ]) }

    it { expect(result).to be_failure }
    it { expect(result).not_to be_success }

    it "exposes the first error" do
      expect(result.error).to eq("boom")
    end
  end

  it "wraps a single error string in an array" do
    expect(described_class.new(errors: "oops").errors).to eq([ "oops" ])
  end

  it "defaults to a successful, dataless result" do
    result = described_class.new
    expect(result).to be_success
    expect(result.data).to be_nil
  end
end
