# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Api::V1::GroupMembershipsController", type: :request do
  # rubocop:enable RSpec/DescribeClass
  let(:user)    { create(:user) }
  let(:owner)   { create(:user) }
  let(:headers) { { "User-Agent" => "rspec" } }

  # Mirrors Groups::CreateGroup: a group plus its owner's membership.
  def group_owned_by(group_owner, **attrs)
    group = create(:group, owner: group_owner, **attrs)
    create(:group_membership, group: group, user: group_owner)
    group
  end

  describe "DELETE /api/v1/groups/:group_id/membership" do
    it "returns 401 when unauthenticated" do
      group = group_owned_by(owner)

      delete "/api/v1/groups/#{group.id}/membership", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { login_as(user, scope: :user) }

      it "removes a non-owner member's membership (204)" do
        group = group_owned_by(owner)
        create(:group_membership, group: group, user: user)

        delete "/api/v1/groups/#{group.id}/membership", headers: headers

        expect(response).to have_http_status(:no_content)
        expect(group.reload.users).not_to include(user)
      end

      it "is idempotent: leaving a group the user is not in returns 204" do
        group = group_owned_by(owner)

        delete "/api/v1/groups/#{group.id}/membership", headers: headers

        expect(response).to have_http_status(:no_content)
      end

      it "returns 422 when the owner tries to leave their own group" do
        group = group_owned_by(user)

        delete "/api/v1/groups/#{group.id}/membership", headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(group.reload.users).to include(user) # still a member
      end

      it "returns 422 when leaving the general pool" do
        pool = create(:group, :general_pool, owner: owner)
        create(:group_membership, group: pool, user: user)

        delete "/api/v1/groups/#{pool.id}/membership", headers: headers

        expect(response).to have_http_status(:unprocessable_content)
        expect(pool.reload.users).to include(user)
      end

      it "returns 404 when the group does not exist" do
        delete "/api/v1/groups/0/membership", headers: headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
