# frozen_string_literal: true

require "rails_helper"
require "rake"

# Integration test for the admin:* rake tasks. Verifies the CLI wiring (task
# discovery, argument parsing, output, exit semantics); the underlying logic
# lives in the Admin::* services and is covered by their own specs.
RSpec.describe "admin rake tasks" do # rubocop:disable RSpec/DescribeClass
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name.start_with?("admin:") }
  end

  before { %w[admin:promote admin:demote admin:list].each { |name| Rake::Task[name].reenable } }

  describe "admin:promote" do
    it "sets admin=true on the matching user" do
      user = create(:user)

      expect { Rake::Task["admin:promote"].invoke(user.email) }
        .to output(/Promoted #{Regexp.escape(user.email)} to admin/).to_stdout
        .and change { user.reload.admin }.from(false).to(true)
    end

    it "aborts when no user matches" do
      expect { Rake::Task["admin:promote"].invoke("ghost@example.com") }
        .to raise_error(SystemExit, /Failed to promote ghost@example.com/)
    end
  end

  describe "admin:demote" do
    it "sets admin=false on the matching user" do
      user = create(:user, :admin)

      expect { Rake::Task["admin:demote"].invoke(user.email) }
        .to output(/Demoted #{Regexp.escape(user.email)} from admin/).to_stdout
        .and change { user.reload.admin }.from(true).to(false)
    end
  end

  describe "admin:list" do
    it "prints admin emails sorted, one per line" do
      create(:user, :admin, email: "alice@example.com")
      create(:user, email: "bob@example.com") # not admin
      create(:user, :admin, email: "carol@example.com")

      expect { Rake::Task["admin:list"].invoke }
        .to output("alice@example.com\ncarol@example.com\n").to_stdout
    end
  end
end
