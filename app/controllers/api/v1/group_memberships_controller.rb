# frozen_string_literal: true

module Api
  module V1
    # Self-service membership: the current user leaving a group. There is no
    # ownership/membership pre-check here — leaving is self-scoped, and the
    # rejections (owner can't leave, general pool can't be left) are returned by
    # Groups::LeaveGroup as a 422. Leaving a group you're not in is a no-op (204).
    class GroupMembershipsController < BaseController
      # DELETE /api/v1/groups/:group_id/membership
      def destroy
        group = Group.find(params[:group_id])
        result = Groups::LeaveGroup.call(user: current_user, group: group)
        return render_validation_error(result.errors) if result.failure?

        head :no_content
      end
    end
  end
end
