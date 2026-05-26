require "rails_helper"

RSpec.describe Service do
  describe ".call" do
    it "returns a successful ServiceResult when #call succeeds" do
      service = Class.new(described_class) do
        def call
          success("ok")
        end
      end

      result = service.call

      expect(result).to be_a(ServiceResult)
      expect(result).to be_success
      expect(result.data).to eq("ok")
    end

    it "returns a failed ServiceResult from the failure helper" do
      service = Class.new(described_class) do
        def call
          failure([ "nope" ])
        end
      end

      result = service.call

      expect(result).to be_failure
      expect(result.errors).to eq([ "nope" ])
    end

    it "rescues Penca::ServiceError and returns its message" do
      service = Class.new(described_class) do
        def call
          raise_service_error("business rule broke")
        end
      end

      result = service.call

      expect(result).to be_failure
      expect(result.error).to eq("business rule broke")
    end

    it "rescues ActiveRecord::RecordInvalid and returns the record's errors" do
      service = Class.new(described_class) do
        def call
          record = Class.new do
            include ActiveModel::Model
            attr_accessor :email
            validates :email, presence: true

            def self.name
              "FakeRecord"
            end
          end.new
          record.validate
          raise ActiveRecord::RecordInvalid, record
        end
      end

      result = service.call

      expect(result).to be_failure
      expect(result.errors).to include("Email can't be blank")
    end

    it "rescues ActiveRecord::RecordNotFound and returns an i18n message" do
      service = Class.new(described_class) do
        def call
          raise ActiveRecord::RecordNotFound
        end
      end

      result = service.call

      expect(result).to be_failure
      expect(result.error).to eq(I18n.t("services.errors.record_not_found", default: "Record not found"))
    end

    it "rescues any other StandardError and returns its message" do
      service = Class.new(described_class) do
        def call
          raise "unexpected"
        end
      end

      result = service.call

      expect(result).to be_failure
      expect(result.error).to eq("unexpected")
    end

    it "requires subclasses to implement #call" do
      expect { Class.new(described_class).call }.to raise_error(NotImplementedError)
    end
  end

  describe "#raise_service_error" do
    it "raises Penca::ServiceError with the given message" do
      service = Class.new(described_class).new

      expect { service.send(:raise_service_error, "msg") }
        .to raise_error(Penca::ServiceError, "msg")
    end
  end

  describe "#invoke" do
    let(:service) { Class.new(described_class).new }

    it "returns the nested result's data on success" do
      expect(service.send(:invoke) { ServiceResult.new(data: 42) }).to eq(42)
    end

    it "raises StandardError when the nested result fails" do
      expect { service.send(:invoke) { ServiceResult.new(errors: [ "nope" ]) } }
        .to raise_error(StandardError, /nope/)
    end
  end
end
