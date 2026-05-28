# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsernameFormatValidator do
  # A bare ActiveModel host to prove the validator is model-agnostic.
  let(:model_class) do
    Class.new do
      include ActiveModel::Validations
      attr_accessor :handle

      def self.name = "Reusable"

      validates :handle, username_format: true
    end
  end

  def build(handle)
    model_class.new.tap { |r| r.handle = handle }
  end

  it "accepts a typical lowercase handle" do
    expect(build("alice_99")).to be_valid
  end

  it "accepts the minimum length (3 chars)" do
    expect(build("ann")).to be_valid
  end

  it "accepts the maximum length (20 chars)" do
    expect(build("a" * 20)).to be_valid
  end

  it "skips blank values (combine with presence: true to require)" do
    expect(build(nil)).to be_valid
    expect(build("")).to be_valid
  end

  it "rejects uppercase letters" do
    record = build("Alice")

    expect(record).not_to be_valid
    expect(record.errors).to be_added(:handle, :invalid)
  end

  it "rejects hyphens" do
    expect(build("alice-99")).not_to be_valid
  end

  it "rejects spaces" do
    expect(build("alice 99")).not_to be_valid
  end

  it "rejects punctuation and other special chars" do
    %w[alice.99 alice@99 alice!99 alice+99].each do |bad|
      expect(build(bad)).not_to be_valid, "expected #{bad.inspect} to be rejected"
    end
  end

  it "rejects values shorter than 3 chars" do
    expect(build("ab")).not_to be_valid
  end

  it "rejects values longer than 20 chars" do
    expect(build("a" * 21)).not_to be_valid
  end
end
