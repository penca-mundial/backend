require "rails_helper"

RSpec.describe ApplicationQuery do
  it "delegates .call to a new instance" do
    query = Class.new(described_class) do
      def call
        "result"
      end
    end

    expect(query.call).to eq("result")
  end

  it "exposes the relation passed to the initializer" do
    query = Class.new(described_class) do
      def call
        relation
      end
    end

    expect(query.call(:scope)).to eq(:scope)
  end

  it "requires subclasses to implement #call" do
    expect { Class.new(described_class).call }.to raise_error(NotImplementedError)
  end
end
