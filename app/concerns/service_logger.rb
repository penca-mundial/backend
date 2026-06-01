# Mixin that gives an object tagged logging helpers. Log lines are prefixed
# with the including class name so service output is easy to grep.
module ServiceLogger
  def log_info(message)
    Rails.logger.info("[#{self.class.name}] #{message}")
  end

  def log_warn(message)
    Rails.logger.warn("[#{self.class.name}] #{message}")
  end

  def log_error(message)
    Rails.logger.error("[#{self.class.name}] #{message}")
  end
end
