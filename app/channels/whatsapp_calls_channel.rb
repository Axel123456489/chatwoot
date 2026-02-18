# frozen_string_literal: true

# ActionCable channel for WhatsApp call real-time updates
class WhatsappCallsChannel < ApplicationCable::Channel
  def subscribed
    ensure_account_connection

    if params[:call_id].present?
      # Subscribe to specific call
      stream_for_call(params[:call_id])
    elsif params[:conversation_id].present?
      # Subscribe to conversation calls
      stream_for_conversation(params[:conversation_id])
    else
      # Subscribe to all account calls
      stream_for_account
    end
  end

  def unsubscribed
    stop_all_streams
  end

  # Client can request call status
  def request_status(data)
    return if data['call_id'].blank?

    call = WhatsappCall.find_by(call_id: data['call_id'])

    return unless call && authorized_for_call?(call)

    transmit({
               type: 'status_update',
               call_id: call.call_id,
               status: call.status,
               duration: call.duration_formatted,
               metadata: {
                 direction: call.direction,
                 initiated_at: call.initiated_at&.iso8601,
                 connected_at: call.connected_at&.iso8601,
                 ended_at: call.ended_at&.iso8601
               }
             })
  rescue StandardError => e
    Rails.logger.error "[WhatsappCallsChannel] Failed to transmit status: #{e.message}"
  end

  # Client sends quality metrics
  def report_quality(data)
    return unless data['call_id'].present? && data['metric_name'].present?

    call = WhatsappCall.find_by(call_id: data['call_id'])

    return unless call && authorized_for_call?(call)

    # Validate metric name to prevent injection
    return unless valid_metric_name?(data['metric_name'])

    call.record_quality_metric(data['metric_name'], data['value'])
  rescue StandardError => e
    Rails.logger.error "[WhatsappCallsChannel] Failed to record quality metric: #{e.message}"
  end

  private

  def valid_metric_name?(name)
    # Whitelist allowed metric names
    %w[
      audio_quality
      video_quality
      packet_loss
      jitter
      round_trip_time
      bandwidth
    ].include?(name)
  end

  def ensure_account_connection
    reject unless current_user && current_account
  end

  def stream_for_call(call_id)
    call = WhatsappCall.find_by(call_id: call_id)

    if call && authorized_for_call?(call)
      stream_from "whatsapp_call_#{call.id}"
      Rails.logger.info "[WhatsappCallsChannel] User #{current_user.id} subscribed to call #{call_id}"
    else
      reject
    end
  end

  def stream_for_conversation(conversation_id)
    conversation = current_account.conversations.find_by(display_id: conversation_id)

    if conversation && authorized_for_conversation?(conversation)
      stream_from "conversation_calls_#{conversation.id}"
      Rails.logger.info "[WhatsappCallsChannel] User #{current_user.id} subscribed to conversation #{conversation_id} calls"
    else
      reject
    end
  end

  def stream_for_account
    stream_from "account_calls_#{current_account.id}"
    Rails.logger.info "[WhatsappCallsChannel] User #{current_user.id} subscribed to account calls"
  end

  def authorized_for_call?(call)
    call.account_id == current_account.id &&
      authorized_for_conversation?(call.conversation)
  end

  def authorized_for_conversation?(conversation)
    # Check if user has access to this conversation's inbox
    return false unless conversation

    Current.user = current_user
    ConversationPolicy.new(current_user, conversation).show?
  rescue Pundit::NotAuthorizedError
    false
  end
end
