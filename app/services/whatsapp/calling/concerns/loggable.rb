# frozen_string_literal: true

module Whatsapp::Calling::Concerns::Loggable
  extend ActiveSupport::Concern

  private

  def log_info(message, **metadata)
    return unless Rails.logger.info?

    log_message = "[#{log_prefix}] #{message}"
    log_message += " #{metadata.inspect}" if metadata.present?
    Rails.logger.info(log_message)
  end

  def log_error(message, exception: nil, **metadata)
    log_message = "[#{log_prefix}] #{message}"
    log_message += " #{metadata.inspect}" if metadata.present?

    Rails.logger.error(log_message)

    return unless exception

    Rails.logger.error("[#{log_prefix}] Exception: #{exception.class} - #{exception.message}")
    Rails.logger.error(exception.backtrace.first(5).join("\n")) if exception.backtrace
  end

  def log_warn(message, **metadata)
    return unless Rails.logger.warn?

    log_message = "[#{log_prefix}] #{message}"
    log_message += " #{metadata.inspect}" if metadata.present?
    Rails.logger.warn(log_message)
  end

  def log_prefix
    self.class.name.demodulize
  end
end
