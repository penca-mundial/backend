# Controller concern that gates an endpoint behind the admin role. Use together
# with Authenticatable (require_user! first), e.g.:
#
#   include AdminAuthorizable
#   before_action :require_admin!
module AdminAuthorizable
  extend ActiveSupport::Concern

  private

  # 403 unless the current user is an admin.
  def require_admin!
    return if current_user&.admin?

    render_error(
      code: "forbidden",
      message: I18n.t("errors.admin_required", default: "No tenés permisos para esta acción."),
      status: :forbidden
    )
  end
end
