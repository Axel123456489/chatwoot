class Whatsapp::Calling::CallStatusJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(account_id:, inbox_id:, status_data:, metadata:)
    account = Account.find(account_id)
    inbox = Inbox.find(inbox_id)

    Whatsapp::Calling::CallStatusService.new(
      account: account,
      inbox: inbox,
      status_data: status_data,
      metadata: metadata
    ).perform
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[WHATSAPP_CALLS] CallStatusJob - Record not found: #{e.message}"
    # Don't retry if account or inbox is deleted
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALLS] CallStatusJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end
end
