class Whatsapp::Calling::BusinessCallConnectService
  include Whatsapp::Calling::Concerns::Loggable
  include Whatsapp::Calling::Concerns::CallFinder
  include Whatsapp::Calling::Concerns::Broadcastable

  def initialize(account:, inbox:, call_data:, metadata:)
    @account = account
    @inbox = inbox
    @channel = @inbox.channel
    @call_data = call_data
    @metadata = metadata
    @call_id = call_data['id']
    @sdp_answer = call_data.dig('session', 'sdp')
  end

  def perform
    validate_calling_enabled!

    conversation = find_conversation
    return log_error('Conversation not found', call_id: @call_id) unless conversation

    process_sdp_answer(conversation) if @sdp_answer.present?
    update_conversation(conversation)
    # NOTE: Connected message intentionally not created here.
    # We only show 2 messages per call: initiated + completed (with recording).
  end

  private

  def validate_calling_enabled!
    return if @channel&.calling_enabled?

    raise StandardError, 'Calling is not enabled for this channel'
  end

  def find_conversation
    # Try metadata first
    conversation_id = @metadata.is_a?(Hash) ? @metadata['conversation_id'] : nil
    conversation = @account.conversations.find_by(id: conversation_id) if conversation_id.present?
    return conversation if conversation

    # Fallback to call_id lookup
    return nil if @call_id.blank?

    find_conversation_by_call_id(@call_id)
  end

  def process_sdp_answer(conversation)
    store_sdp_answer(conversation)
    notify_browser_answer_ready(conversation)
  rescue StandardError => e
    log_error('Error processing SDP answer', exception: e, call_id: @call_id)
  end

  def store_sdp_answer(conversation)
    return unless conversation

    attrs = (conversation.additional_attributes || {}).deep_dup
    whatsapp_call = attrs['whatsapp_call'] || {}

    whatsapp_call['whatsapp_sdp_answer'] = @sdp_answer
    whatsapp_call['sdp_answer'] = @sdp_answer
    whatsapp_call['whatsapp_answer_received_at'] = Time.current.to_i

    attrs['whatsapp_call'] = whatsapp_call
    # CRITICAL: Preserve call_id at top level for terminate webhook lookup
    attrs['call_id'] = @call_id if @call_id.present?
    conversation.update!(additional_attributes: attrs)
  rescue StandardError => e
    log_error('Failed to store SDP answer', exception: e)
  end

  def notify_browser_answer_ready(conversation)
    whatsapp_call = conversation.additional_attributes&.dig('whatsapp_call') || {}
    sdp_answer = whatsapp_call['whatsapp_sdp_answer'] || whatsapp_call['sdp_answer']

    broadcast_sdp_answer(conversation, @call_id, sdp_answer)
  rescue StandardError => e
    log_error('Failed to notify browser', exception: e)
  end

  def update_conversation(conversation)
    additional_attrs = conversation.additional_attributes || {}
    additional_attrs['call_status'] = 'connecting'
    additional_attrs['sdp_answer_received_at'] = Time.current.to_i
    additional_attrs['media_connected'] = MediaServerConfig.enabled?
    # CRITICAL: Preserve call_id at top level for terminate webhook lookup
    additional_attrs['call_id'] = @call_id if @call_id.present?

    conversation.update!(additional_attributes: additional_attrs)
    update_whatsapp_call(conversation)
  end

  def update_whatsapp_call(conversation)
    whatsapp_call = find_whatsapp_call(call_id: @call_id, conversation: conversation)
    return log_error('WhatsappCall not found', call_id: @call_id) unless whatsapp_call

    transition_to_connected(whatsapp_call)
    # NOTE: Don't create connected message - it creates duplicates
    # We only need initiated + completed messages
    # create_connected_message(conversation, whatsapp_call)
  end

  def create_connect_message(conversation)
    whatsapp_call = find_whatsapp_call(call_id: @call_id, conversation: conversation)
    return log_error('WhatsappCall not found', call_id: @call_id) unless whatsapp_call

    # Avoid duplicate connected messages when webhook retried
    already_connected = conversation.messages.exists?(content_type: :voice_call, call_status: :connected)
    return if already_connected

    builder = Whatsapp::Calling::CallMessageBuilder.new(
      conversation: conversation,
      whatsapp_call: whatsapp_call
    )

    builder.create_connected_message
  rescue StandardError => e
    log_error('Failed to create connected message', exception: e, call_id: @call_id)
  end

  def transition_to_connected(whatsapp_call)
    case whatsapp_call.status.to_sym
    when :initiated
      [:ring, :accept, :connect].each do |event|
        whatsapp_call.public_send("#{event}!") if whatsapp_call.public_send("may_#{event}?")
      end
    when :ringing
      [:accept, :connect].each do |event|
        whatsapp_call.public_send("#{event}!") if whatsapp_call.public_send("may_#{event}?")
      end
    when :accepted, :connecting
      whatsapp_call.connect! if whatsapp_call.may_connect?
    when :connected
      whatsapp_call.update!(connected_at: Time.current) if whatsapp_call.connected_at.nil?
    end
  end

  def create_connected_message(conversation, whatsapp_call)
    builder = Whatsapp::Calling::CallMessageBuilder.new(
      conversation: conversation,
      whatsapp_call: whatsapp_call
    )

    builder.create_connected_message
  rescue StandardError => e
    log_error('Failed to create connected message', exception: e)
  end
end
