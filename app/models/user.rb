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

  # Group membership: a user joins many groups through their memberships, and
  # may own up to MAX_OWNED_GROUPS of them. The FKs have no ON DELETE cascade,
  # so dependent: :destroy is what cleans these up when a user is removed.
  has_many :memberships, class_name: "GroupMembership", dependent: :destroy
  has_many :groups, through: :memberships
  has_many :owned_groups, class_name: "Group", foreign_key: :owner_id, dependent: :destroy, inverse_of: :owner

  # Predictions and their derived scores. prediction_scores is reached through
  # predictions (see Prediction#prediction_scores).
  has_many :predictions, dependent: :destroy
  has_many :tournament_predictions, dependent: :destroy
  has_many :ranking_snapshots, dependent: :destroy
  has_many :prediction_scores, through: :predictions

  # Usernames are stored lowercase (see #normalize_username); the shared
  # UsernameFormatValidator enforces the [a-z0-9_]{3,20} shape. Presence is
  # required for every user EXCEPT a freshly-provisioned OAuth user, who
  # picks their handle in the onboarding flow right after the callback.
  validates :username, presence: true, unless: :oauth_pending_username?
  validates :username,
            username_format: true,
            uniqueness: { case_sensitive: false, allow_blank: true }
  # Custom and Google avatars are both https; reject anything else (or malformed).
  # Optional — blank is fine (the user may have no avatar).
  validates :avatar_url, https_url: true, allow_blank: true
  validate :password_contains_digit

  before_validation :normalize_username
  before_save :promote_admin_from_env

  # General pool enrolment: fires when a user becomes confirmed — either
  # because Google OAuth created them already confirmed, or because they
  # clicked the confirmation link. The system account is excluded; it exists
  # only to satisfy owner_id FKs and must not appear in any group.
  after_commit :enqueue_general_pool_enrolment, on: %i[create update],
               if: :general_pool_enrolment_due?

  # Users who have not been banned.
  scope :active, -> { where(banned_at: nil) }

  def banned?
    banned_at.present?
  end

  # Devise hook: banned users and the service account can never authenticate.
  def active_for_authentication?
    super && !banned? && !system?
  end

  # Send every Devise email (confirmation, password reset) through Solid Queue
  # instead of inline. Devise's AR confirmable already fires this in an
  # after_commit callback (outside the create transaction), so deliver_later
  # only ENQUEUES a job here — the provider (Resend) is never called on the
  # request path. A provider outage therefore can't roll back the signup, can't
  # leave the user blocked, and can't surface a raw error to the form; the job
  # retries on its own. Overrides the gem default, which uses deliver_now.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
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

  def general_pool_enrolment_due?
    return false if system?
    return false if confirmed_at.blank?

    # On create the change set always names confirmed_at if it was passed in;
    # on update we only care when confirmed_at itself just changed.
    saved_change_to_confirmed_at? || previously_new_record?
  end

  def enqueue_general_pool_enrolment
    AddUserToGeneralPoolJob.perform_later(id)
  end
end
