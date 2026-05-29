# frozen_string_literal: true

module Api
  module V1
    module Auth
      # GET /api/v1/auth/me — return the currently authenticated user.
      # The frontend hits this on every page load to know who is logged in.
      class MeController < BaseController
        def show
          render json: {
            user: UserBlueprint.render_as_hash(current_user)
                               .merge(needs_username: current_user.username.blank?)
          }
        end
      end
    end
  end
end
