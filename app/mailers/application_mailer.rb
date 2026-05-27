class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Penca Mundial <no-reply@penca.local>")
  layout "mailer"
end
