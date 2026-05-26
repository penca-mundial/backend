class ApplicationController < ActionController::API
  before_action :set_paper_trail_whodunnit

  private

  # Record who made a change for PaperTrail. `current_user` only exists once a
  # Devise mapping is wired up (Phase 1/2), so guard against its absence.
  def set_paper_trail_whodunnit
    PaperTrail.request.whodunnit = current_user&.id if respond_to?(:current_user)
  end
end
