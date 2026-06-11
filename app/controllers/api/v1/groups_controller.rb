# frozen_string_literal: true

module Api
  module V1
    # Authenticated group endpoints (all under BaseController#require_user!).
    # Thin: each action authorizes (membership / ownership) up front for the right
    # status, then delegates the work to a Groups::* service and serializes.
    # Authorization here returns 403 before the service runs; the services' own
    # guards remain as defense in depth.
    class GroupsController < BaseController
      # GET /api/v1/groups/me
      def index
        groups = current_user.groups.includes(:owner).order(is_general_pool: :desc, created_at: :desc).to_a
        render json: GroupBlueprint.render(
          groups,
          current_user:  current_user,
          member_counts: member_counts_for(groups),
          my_ranks:      ranks_for(groups)
        ), content_type: "application/json"
      end

      # POST /api/v1/groups
      def create
        result = Groups::CreateGroup.call(
          owner: current_user, name: group_params[:name], description: group_params[:description]
        )
        return render_validation_error(result.errors) if result.failure?

        render json: group_hash(result.data[:group]), status: :created
      end

      # GET /api/v1/groups/:id
      def show
        group = Group.includes(:owner).find(params[:id])
        return render_forbidden unless member?(group)

        render json: group_hash(group)
      end

      # PATCH /api/v1/groups/:id
      def update
        group = Group.find(params[:id])
        return render_forbidden unless owner?(group)

        result = Groups::UpdateGroup.call(
          group: group, name: group_params[:name], description: group_params[:description]
        )
        return render_validation_error(result.errors) if result.failure?

        render json: group_hash(result.data[:group])
      end

      # DELETE /api/v1/groups/:id
      def destroy
        group = Group.find(params[:id])
        return render_forbidden unless owner?(group)

        result = Groups::DeleteGroup.call(owner: current_user, group: group)
        return render_validation_error(result.errors) if result.failure?

        head :no_content
      end

      # POST /api/v1/groups/join
      def join
        result = Groups::JoinGroup.call(user: current_user, code: params[:code])
        return render_validation_error(result.errors) if result.failure?

        status = result.data[:joined] ? :created : :ok
        render json: group_hash(result.data[:membership].group), status: status
      end

      # POST /api/v1/groups/:id/regenerate_code
      def regenerate_code
        group = Group.find(params[:id])
        return render_forbidden unless owner?(group)

        result = Groups::RegenerateCode.call(owner: current_user, group: group)
        return render_validation_error(result.errors) if result.failure?

        render json: group_hash(result.data[:group])
      end

      # GET /api/v1/groups/:id/members
      def members
        group = Group.find(params[:id])
        return render_forbidden unless member?(group)

        memberships = group.memberships.includes(:user).order(:joined_at)
        render_paginated(memberships, GroupMemberBlueprint, owner_id: group.owner_id)
      end

      # DELETE /api/v1/groups/:id/members/:user_id
      def kick_member
        group = Group.find(params[:id])
        return render_forbidden unless owner?(group)

        result = Groups::KickMember.call(
          owner: current_user, group: group, target_user: User.find(params[:user_id])
        )
        return render_validation_error(result.errors) if result.failure?

        head :no_content
      end

      private

      def group_params
        params.permit(:name, :description)
      end

      def owner?(group)
        group.owner_id == current_user.id
      end

      # member_count is computed for the single group; collections pass a batched
      # {group_id => count} hash instead (see #index).
      def group_hash(group)
        GroupBlueprint.render_as_hash(
          group, current_user: current_user, member_counts: { group.id => group.memberships.count }
        )
      end

      def member_counts_for(groups)
        GroupMembership.where(group_id: groups.map(&:id)).group(:group_id).count
      end

      # {group_id => rank} for the current user, reusing the rankings query. The
      # leaderboard is tournament-scoped (pencas are not), so it resolves the
      # current tournament here; nil when none exists -> an empty hash (no rank).
      def ranks_for(groups)
        GroupRanksQuery.call(user: current_user, tournament: CurrentTournamentQuery.call, groups: groups)
      end
    end
  end
end
