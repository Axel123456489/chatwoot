# frozen_string_literal: true

# Repository pattern for WhatsApp calls
# Encapsulates all database operations for WhatsappCall model
class Whatsapp::Calling::CallRepository
  # Create a new call
  def create_call(account:, conversation:, contact:, inbox:, user:, call_id:, direction:, **attrs)
    WhatsappCall.create!(
      account: account,
      conversation: conversation,
      contact: contact,
      inbox: inbox,
      initiated_by_user: user,
      call_id: call_id,
      direction: direction,
      initiated_at: Time.current,
      **attrs
    )
  end

  # Find call by call_id
  def find_by_call_id(call_id)
    WhatsappCall.find_by(call_id: call_id)
  end

  # Find call by call_id with error if not found
  def find_by_call_id!(call_id)
    WhatsappCall.find_by!(call_id: call_id)
  end

  # Find active call for conversation
  def find_active_call(conversation:)
    conversation.whatsapp_calls.active.order(created_at: :desc).first
  end

  # Check if conversation has active call
  def has_active_call?(conversation:)
    find_active_call(conversation: conversation).present?
  end

  # Get call history for conversation
  def conversation_history(conversation:, limit: 20, offset: 0)
    conversation.whatsapp_calls
                .recent
                .limit(limit)
                .offset(offset)
  end

  # Get call history for contact
  def contact_history(contact:, limit: 20, offset: 0)
    contact.whatsapp_calls
           .recent
           .limit(limit)
           .offset(offset)
  end

  # Update call status (using state machine)
  def transition_status!(call:, event:, reason: nil)
    call.aasm.fire!(event)
    call.update!(status_reason: reason) if reason.present?
    call
  rescue AASM::InvalidTransition => e
    Rails.logger.error "[CallRepository] Invalid transition: #{e.message}"
    raise
  end

  # Update call metadata
  def update_metadata(call:, **metadata)
    current_metadata = call.metadata || {}
    call.update!(metadata: current_metadata.merge(metadata))
  end

  # Store SDP information
  def store_sdp(call:, browser_offer: nil, whatsapp_answer: nil)
    updates = {}
    updates[:browser_sdp_offer] = browser_offer if browser_offer
    updates[:whatsapp_sdp_answer] = whatsapp_answer if whatsapp_answer

    call.update!(updates) if updates.any?
  end

  # Get analytics for account
  def analytics(account:, start_date:, end_date:, inbox_id: nil)
    calls = account.whatsapp_calls.for_date_range(start_date, end_date)
    calls = calls.where(inbox_id: inbox_id) if inbox_id

    {
      total_calls: calls.count,
      outbound_calls: calls.direction_outbound.count,
      inbound_calls: calls.direction_inbound.count,
      successful_calls: calls.successful.count,
      failed_calls: calls.where(aasm_state: 'failed').count,
      rejected_calls: calls.where(aasm_state: 'rejected').count,
      average_duration: calls.successful.average(:duration_seconds)&.to_f&.round(2),
      total_duration: calls.successful.sum(:duration_seconds)
    }
  end

  # Get recent calls by status
  def calls_by_status(account:, status:, limit: 100)
    account.whatsapp_calls
           .where(aasm_state: status)
           .recent
           .limit(limit)
  end

  # Find calls that need cleanup (stale calls)
  def find_stale_calls(timeout_minutes: 30)
    WhatsappCall.active
                .where('updated_at < ?', timeout_minutes.minutes.ago)
  end

  # Cleanup stale calls
  def cleanup_stale_calls!(timeout_minutes: 30)
    stale_calls = find_stale_calls(timeout_minutes)

    stale_calls.each do |call|
      call.timeout! if call.may_timeout?
    rescue StandardError => e
      Rails.logger.error "[CallRepository] Failed to timeout call #{call.call_id}: #{e.message}"
    end

    stale_calls.count
  end

  # Bulk update
  def bulk_update(call_ids:, **attributes)
    WhatsappCall.where(call_id: call_ids).update_all(attributes)
  end
end
