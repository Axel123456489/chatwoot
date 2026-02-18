class Whatsapp::Calling::CallTerminateJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(account_id:, inbox_id:, call_data:, metadata:)
    Rails.logger.info "[WHATSAPP_CALLS] CallTerminateJob starting - call_id: #{call_data['id']}, status: #{call_data['status']}, duration: #{call_data['duration']}"

    account = Account.find(account_id)
    inbox = Inbox.find(inbox_id)

    Whatsapp::Calling::CallTerminateService.new(
      account: account,
      inbox: inbox,
      call_data: call_data,
      metadata: metadata
    ).perform

    Rails.logger.info "[WHATSAPP_CALLS] CallTerminateJob completed - call_id: #{call_data['id']}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[WHATSAPP_CALLS] CallTerminateJob - Record not found: #{e.message}"
    # Don't retry if account or inbox is deleted
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP_CALLS] CallTerminateJob failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise
  end
end
