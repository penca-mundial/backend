# frozen_string_literal: true

require "rails_helper"

RSpec.describe FutureDateValidator do
  include ActiveSupport::Testing::TimeHelpers

  # A bare ActiveModel host to prove the validator is model-agnostic.
  let(:model_class) do
    Class.new do
      include ActiveModel::Validations
      attr_accessor :starts_at

      def self.name = "Reusable"

      validates :starts_at, future_date: true
    end
  end

  def build(starts_at)
    model_class.new.tap { |r| r.starts_at = starts_at }
  end

  it "accepts a future Time" do
    expect(build(1.hour.from_now)).to be_valid
  end

  it "accepts a future Date" do
    expect(build(Date.tomorrow)).to be_valid
  end

  it "rejects a past Time" do
    record = build(1.hour.ago)

    expect(record).not_to be_valid
    expect(record.errors).to be_added(:starts_at, :not_in_future)
  end

  it "rejects a past Date" do
    expect(build(Date.yesterday)).not_to be_valid
  end

  it "rejects the current Time (not strictly in the future)" do
    travel_to Time.zone.local(2026, 1, 1, 12) do
      expect(build(Time.current)).not_to be_valid
    end
  end

  it "skips blank values (combine with presence: true to require)" do
    expect(build(nil)).to be_valid
  end
end
