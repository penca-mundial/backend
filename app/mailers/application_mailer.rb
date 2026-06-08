class ApplicationMailer < ActionMailer::Base
  # The sender address comes from MAILER_FROM so production points at a verified
  # Resend domain (e.g. "Penca Mundial <no-reply@magicpenca.app>"); the default
  # is a real-domain placeholder, never the unsendable @penca.local. Resolved at
  # delivery time (a proc) so it follows the env, not the boot-time value.
  default from: ->(*) { ApplicationMailer.from_address }
  layout "mailer"

  DEFAULT_FROM = "Penca Mundial <no-reply@magicpenca.app>"

  def self.from_address
    ENV.fetch("MAILER_FROM", DEFAULT_FROM)
  end
end
