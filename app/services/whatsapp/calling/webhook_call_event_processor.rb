# frozen_string_literal: true

class Whatsapp::Calling::WebhookCallEventProcessor
  include Whatsapp::Calling::Concerns::Loggable

  def initialize(channel:, debug: false)
    @channel = channel
    @inbox = channel.inbox
    @account = @inbox.account
    @debug = debug
  end

  def perform(value)
    log_debug { "Call webhook payload keys: #{value&.keys}" }

    statuses = value[:statuses]
    process_call_statuses(statuses) if statuses.is_a?(Array)

    calls = value[:calls]
    process_call_events(calls) if calls.is_a?(Array)

    return if statuses.is_a?(Array) || calls.is_a?(Array)

    Rails.logger.warn '[WHATSAPP_CALLING] Call webhook has neither statuses nor calls array'
  end

  private

  def log_debug
    return unless @debug

    Rails.logger.debug { "[WHATSAPP_CALLING] #{yield}" }
  end

  def process_call_statuses(statuses)
    log_debug { "statuses count: #{statuses.length}" }
    statuses.each { |status| process_call_status(status) }
  end

  def process_call_status(status)
    return unless status[:type] == 'call'

    call_id = status[:id]
    call_status = status[:status]
    recipient_id = status[:recipient_id]
    sdp_answer = status.dig(:session, :sdp)

    log_debug do
      "Call status=#{call_status} call_id=#{call_id} recipient=#{recipient_id} sdp_present=#{sdp_answer.present?}"
    end

    return unless call_status == 'RINGING' || call_status == 'ACCEPTED'

    enqueue_call_status_job(call_id: call_id, status: status)
    process_status_sdp_answer(call_id: call_id, call_status: call_status, sdp_answer: sdp_answer)
  end

  def process_status_sdp_answer(call_id:, call_status:, sdp_answer:)
    return unless call_status == 'ACCEPTED'

    if sdp_answer.blank?
      Rails.logger.warn "[WHATSAPP_EVENTS] ACCEPTED received but no SDP answer call_id=#{call_id}"
      return
    end

    log_debug { "SDP answer received in ACCEPTED status call_id=#{call_id}" }
    broadcast_sdp_answer(call_id: call_id, sdp_answer: sdp_answer)
  end

  def enqueue_call_status_job(call_id:, status:)
    log_debug { "Enqueueing CallStatusJob status=#{status[:status]} call_id=#{call_id}" }

    Whatsapp::Calling::CallStatusJob.perform_later(
      account_id: @account.id,
      inbox_id: @inbox.id,
      status_data: status.as_json,
      metadata: { call_id: call_id }
    )
  end

  def process_call_events(calls)
    log_debug { "calls count: #{calls.length}" }
    calls.each { |call| process_call_event(call) }
  end

  def process_call_event(call)
    attrs = call_event_attributes(call)
    log_call_event(call: call, attrs: attrs)

    case attrs[:event]
    when 'initiated'
      handle_initiated_event(call_id: attrs[:call_id], direction: attrs[:direction], call: call)
    when 'connect'
      handle_connect_event(call_id: attrs[:call_id], direction: attrs[:direction], sdp_answer: attrs[:sdp_answer], call: call)
    when 'terminate'
      Rails.logger.info "[WHATSAPP_EVENTS] Call terminated call_id=#{attrs[:call_id]}"
      process_terminate_event(call)
    else
      Rails.logger.warn "[WHATSAPP_EVENTS] Unhandled call event=#{attrs[:event]} call_id=#{attrs[:call_id]}"
      log_debug { "Unknown event payload: #{call.inspect}" }
    end
  end

  def call_event_attributes(call)
    {
      call_id: call[:id],
      event: call[:event],
      status: call[:status],
      direction: call[:direction],
      sdp_answer: call.dig(:session, :sdp)
    }
  end

  def log_call_event(call:, attrs:)
    log_debug do
      "Call event=#{attrs[:event]} status=#{attrs[:status]} direction=#{attrs[:direction]} " \
        "call_id=#{attrs[:call_id]} sdp_present=#{attrs[:sdp_answer].present?}"
    end
    log_debug { "Call event payload: #{call.inspect}" }
  end

  def handle_initiated_event(call_id:, direction:, call:)
    if direction == 'USER_INITIATED'
      return if skip_inbound_enqueue?(call_id: call_id, reason: 'initiated')

      Rails.logger.info "[WHATSAPP_EVENTS] New inbound call initiated call_id=#{call_id}"
      enqueue_inbound_call_job(call)
      log_debug { "InboundCallJob enqueued (initiated) call_id=#{call_id}" }
      return
    end

    Rails.logger.info "[WHATSAPP_EVENTS] Outbound call initiated call_id=#{call_id}"
  end

  def handle_connect_event(call_id:, direction:, sdp_answer:, call:)
    log_debug { "Call connect event direction=#{direction} call_id=#{call_id}" }

    if direction == 'USER_INITIATED'
      return if skip_inbound_enqueue?(call_id: call_id, reason: 'connect')

      Rails.logger.info "[WHATSAPP_EVENTS] New inbound call (connect event) call_id=#{call_id}"
      enqueue_inbound_call_job(call)
      log_debug { "InboundCallJob enqueued (connect) call_id=#{call_id}" }
      return
    end

    log_debug { "Outbound call connect event call_id=#{call_id}" }

    if sdp_answer.blank?
      Rails.logger.error "[WHATSAPP_EVENTS] No SDP answer in connect event call_id=#{call_id}"
      log_debug { "connect event missing SDP payload: #{call.inspect}" }
      return
    end

    log_debug { "outbound connect has SDP; processing call_id=#{call_id}" }
    broadcast_sdp_answer(call_id: call_id, sdp_answer: sdp_answer)
  end

  def enqueue_inbound_call_job(call)
    Whatsapp::Calling::InboundCallJob.perform_later(
      account_id: @account.id,
      inbox_id: @inbox.id,
      call_data: call.as_json,
      metadata: {}
    )
  end

  def skip_inbound_enqueue?(call_id:, reason:)
    return false unless inbound_call_already_handled?(call_id)

    log_debug { "inbound #{reason} already handled; skipping enqueue call_id=#{call_id}" }
    true
  end

  def inbound_call_already_handled?(call_id)
    @account.conversations.exists?(
      [
        "identifier = :call_id OR additional_attributes->>'call_id' = :call_id OR " \
        "additional_attributes->'whatsapp_call'->>'call_id' = :call_id",
        { call_id: call_id }
      ]
    )
  end

  def broadcast_sdp_answer(call_id:, sdp_answer:)
    Whatsapp::Calling::WebhookSdpAnswerBroadcaster
      .new(account: @account, inbox: @inbox, call_id: call_id, sdp_answer: sdp_answer)
      .perform
  end

  def process_terminate_event(call)
    Whatsapp::Calling::WebhookCallTerminateBroadcaster
      .new(account: @account, inbox: @inbox, call_data: call)
      .perform

    Whatsapp::Calling::CallTerminateJob.perform_later(
      account_id: @account.id,
      inbox_id: @inbox.id,
      call_data: call.as_json,
      metadata: {}
    )
  end
end
