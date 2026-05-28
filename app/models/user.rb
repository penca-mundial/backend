# frozen_string_literal: true

class User < ApplicationRecord
  # :pwned_password is the module exposed by devise-pwned_password; it rejects
  # passwords found in the Have I Been Pwned breach corpus.
  devise :database_authenticatable, :registerable, :recoverable, :rememberable,
         :validatable, :confirmable, :omniauthable, :pwned_password,
         omniauth_providers: [ :google_oauth2 ]

  # Only sensitive role/state changes are audited; routine profile edits
  # (username, password resets, oauth tokens, etc.) stay out of the log.
  has_paper_trail only: [ :admin, :banned_at ]

  # Usernames are stored lowercase (see #normalize_username); the shared
  # UsernameFormatValidator enforces the [a-z0-9_]{3,20} shape. Presence is
  # required for every user EXCEPT a freshly-provisioned OAuth user, who
  # picks their handle in the onboarding flow right after the callback.
  validates :username, presence: true, unless: :oauth_pending_username?
  validates :username,
            username_format: true,
            uniqueness: { case_sensitive: false, allow_blank: true }
  validate :password_contains_digit

  before_validation :normalize_username
  before_save :promote_admin_from_env

  # Users who have not been banned.
  scope :active, -> { where(banned_at: nil) }

  def banned?
    banned_at.present?
  end

  # Devise hook: banned users and the service account can never authenticate.
  def active_for_authentication?
    super && !banned? && !system?
  end

  protected

  # OAuth-provisioned users authenticate through the provider and never set a
  # password, so password presence/length is not required for them.
  def password_required?
    return false if provider.present?

    super
  end

  private

  def normalize_username
    self.username = username.downcase if username.present?
  end

  def oauth_pending_username?
    provider.present? && username.blank?
  end

  def promote_admin_from_env
    self.admin = true if admin_email?
  end

  def admin_email?
    admin_emails.include?(email.to_s.downcase)
  end

  def admin_emails
    ENV.fetch("ADMIN_EMAILS", "").split(",").map { |entry| entry.strip.downcase }
  end

  # Devise's :validatable already enforces the length range (see
  # config.password_length). Here we add only the "at least one digit" rule,
  # skipping records without a password (e.g. OAuth sign-ups).
  def password_contains_digit
    return if password.blank?
    return if password.match?(/\d/)

    errors.add(:password, :missing_digit)
  end
end
