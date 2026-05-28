# frozen_string_literal: true

# Admin role CLI. Thin wrappers around the Admin::* services; output is for the
# human running the task, no API surface here.
namespace :admin do
  desc "Promote the user with the given email to admin"
  task :promote, [ :email ] => :environment do |_task, args|
    result = Admin::PromoteUser.call(email: args[:email])
    abort("Failed to promote #{args[:email]}: #{result.errors.join('; ')}") if result.failure?

    puts "Promoted #{args[:email]} to admin."
  end

  desc "Demote the user with the given email from admin"
  task :demote, [ :email ] => :environment do |_task, args|
    result = Admin::DemoteUser.call(email: args[:email])
    abort("Failed to demote #{args[:email]}: #{result.errors.join('; ')}") if result.failure?

    puts "Demoted #{args[:email]} from admin."
  end

  desc "List the emails of all admins (one per line, sorted)"
  task list: :environment do
    User.where(admin: true).order(:email).pluck(:email).each { |email| puts email }
  end
end
