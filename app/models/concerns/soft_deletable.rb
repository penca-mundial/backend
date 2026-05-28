# frozen_string_literal: true

# Adds soft-delete behaviour to a model backed by a `deleted_at` column.
# Models that include this typically also add a default scope that hides
# soft-deleted records.
module SoftDeletable
  extend ActiveSupport::Concern

  def soft_delete!
    update!(deleted_at: Time.current) unless soft_deleted?
  end

  def restore!
    update!(deleted_at: nil) if soft_deleted?
  end

  def soft_deleted?
    deleted_at.present?
  end
end
