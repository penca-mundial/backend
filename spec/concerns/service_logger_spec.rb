require "rails_helper"

RSpec.describe ServiceLogger do
  subject(:instance) { klass.new }

  let(:klass) do
    Class.new do
      include ServiceLogger

      def self.name
        "DummyLogger"
      end
    end
  end


  it "logs info messages tagged with the class name" do
    expect(Rails.logger).to receive(:info).with("[DummyLogger] hello")
    instance.log_info("hello")
  end

  it "logs error messages tagged with the class name" do
    expect(Rails.logger).to receive(:error).with("[DummyLogger] boom")
    instance.log_error("boom")
  end
end
