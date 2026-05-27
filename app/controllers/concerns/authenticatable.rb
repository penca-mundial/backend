# Controller concern providing the current user (via Warden) and a
# `require_user!` filter. Included in Api::V1::BaseController, which requires an
# authenticated, non-banned user by default; public controllers opt out with
# `skip_before_action :require_user!`.
module Authenticatable
  extend ActiveSupport::Concern

  private

  def current_user
    @current_user ||= request.env["warden"]&.user(:user)
  end

  def user_signed_in?
    current_user.present?
  end

  # 401 when there is no authenticated user, 403 when the user is banned.
  def require_user!
    unless current_user
      return render_error(
        code: "unauthenticated",
        message: I18n.t("errors.unauthenticated", default: "Necesitás iniciar sesión para continuar."),
        status: :unauthorized
      )
    end

    return unless user_banned?

    render_error(
      code: "account_banned",
      message: I18n.t("errors.account_banned", default: "Tu cuenta fue suspendida."),
      status: :forbidden
    )
  end

  def user_banned?
    current_user.respond_to?(:banned_at) && current_user.banned_at.present?
  end
end
