class Whatsapp::Calling::InboundCallJob < ApplicationJob
  queue_as :critical  # High priority - must respond quickly to keep call alive
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(account_id:, inbox_id:, call_data:, metadata:)
    account = Account.find(account_id)
    inbox = Inbox.find(inbox_id)

    Whatsapp::Calling::InboundCallBuilder.new(
      account: account,
      inbox: inbox,
      call_data: call_data,
      metadata: metadata
    ).perform
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[WHATSAPP_CALLS] InboundCallJob - Record not found: #{e.message}"
    # Don't retry if account or inbox is deleted
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALLS] InboundCallJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end
end
