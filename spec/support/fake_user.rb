# Stand-in for the real User model (which arrives in Phase 1), used to exercise
# the auth concerns with Warden test mode.
FakeUser = Struct.new(:id, :admin, :banned_at, keyword_init: true) do
  def admin? = admin
end
