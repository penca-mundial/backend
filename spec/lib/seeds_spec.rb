# frozen_string_literal: true

require "rails_helper"

# Verifies the seed orchestration end to end: on a fresh DB the loader runs
# cleanly, produces the expected baseline counts, and a second invocation is a
# no-op.
RSpec.describe "db/seeds.rb" do # rubocop:disable RSpec/DescribeClass
  let(:seed_path) { Rails.root.join("db/seeds.rb") }

  def run_seeds!
    load(seed_path.to_s)
  end

  it "runs to completion on a fresh database" do
    expect { run_seeds! }.not_to raise_error
  end

  it "produces the expected baseline counts" do
    run_seeds!

    expect(Tournament.count).to eq(1)
    expect(Team.count).to eq(48)
    expect(ScoringRule.count).to eq(9)
    expect(PhaseMultiplier.count).to eq(7)
    expect(User.where(system: true).count).to eq(1)
    expect(Group.unscoped.where(is_general_pool: true).count).to eq(1)
  end

  it "is idempotent: running twice produces the same counts" do
    run_seeds!
    run_seeds!

    expect(Tournament.count).to eq(1)
    expect(Team.count).to eq(48)
    expect(ScoringRule.count).to eq(9)
    expect(PhaseMultiplier.count).to eq(7)
    expect(User.where(system: true).count).to eq(1)
    expect(Group.unscoped.where(is_general_pool: true).count).to eq(1)
  end

  it "anchors the system user as the owner of the general pool" do
    run_seeds!

    system_user = User.find_by!(email: Seeds::SystemUser::EMAIL)
    pool        = Group.unscoped.find_by!(is_general_pool: true)

    expect(pool.owner).to eq(system_user)
    expect(system_user.system?).to be true
  end
end
