class Api::V1::Accounts::ConversationsController < Api::V1::Accounts::BaseController
  include Events::Types
  include DateRangeHelper
  include HmacConcern

  before_action :conversation, except: [:index, :meta, :search, :create, :filter]
  before_action :inbox, :contact, :contact_inbox, only: [:create]

  # Skip authorization for whatsapp_call_recording - it does its own conversation lookup
  skip_before_action :conversation, only: [:whatsapp_call_recording]
  before_action :set_conversation_for_recording, only: [:whatsapp_call_recording]

  ATTACHMENT_RESULTS_PER_PAGE = 100

  def index
    result = conversation_finder.perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  end

  def meta
    result = conversation_finder.perform_meta_only
    @conversations_count = result[:count]
  end

  def search
    result = conversation_finder.perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  end

  def attachments
    @attachments_count = @conversation.attachments.count
    @attachments = @conversation.attachments
                                .includes(:message)
                                .order(created_at: :desc)
                                .page(attachment_params[:page])
                                .per(ATTACHMENT_RESULTS_PER_PAGE)
  end

  def show; end

  def create
    ActiveRecord::Base.transaction do
      @conversation = ConversationBuilder.new(params: params, contact_inbox: @contact_inbox).perform
      Messages::MessageBuilder.new(Current.user, @conversation, params[:message]).perform if params[:message].present?
    end
  end

  def update
    @conversation.update!(permitted_update_params)
  end

  def filter
    result = ::Conversations::FilterService.new(params.permit!, current_user, current_account).perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  def mute
    @conversation.mute!
    head :ok
  end

  def unmute
    @conversation.unmute!
    head :ok
  end

  def transcript
    render json: { error: 'email param missing' }, status: :unprocessable_entity and return if params[:email].blank?
    return head :too_many_requests unless @conversation.account.within_email_rate_limit?

    ConversationReplyMailer.with(account: @conversation.account).conversation_transcript(@conversation, params[:email])&.deliver_later
    @conversation.account.increment_email_sent_count
    head :ok
  end

  def toggle_status
    # FIXME: move this logic into a service object
    if pending_to_open_by_bot?
      @conversation.bot_handoff!
    elsif params[:status].present?
      set_conversation_status
      @status = @conversation.save!
    else
      @status = @conversation.toggle_status
    end
    assign_conversation if should_assign_conversation?
  end

  def pending_to_open_by_bot?
    return false unless Current.user.is_a?(AgentBot)

    @conversation.status == 'pending' && params[:status] == 'open'
  end

  def should_assign_conversation?
    @conversation.status == 'open' && Current.user.is_a?(User) && Current.user&.agent?
  end

  def toggle_priority
    @conversation.toggle_priority(params[:priority])
    head :ok
  end

  def toggle_typing_status
    typing_status_manager = ::Conversations::TypingStatusManager.new(@conversation, current_user, params)
    typing_status_manager.toggle_typing_status
    head :ok
  end

  def update_last_seen
    # High-traffic accounts generate excessive DB writes when agents frequently switch between conversations.
    # Throttle last_seen updates to once per hour when there are no unread messages to reduce DB load.
    # Always update immediately if there are unread messages to maintain accurate read/unread state.
    return update_last_seen_on_conversation(DateTime.now.utc, true) if assignee? && @conversation.assignee_unread_messages.any?
    return update_last_seen_on_conversation(DateTime.now.utc, false) if !assignee? && @conversation.unread_messages.any?

    # No unread messages - apply throttling to limit DB writes
    return unless should_update_last_seen?

    update_last_seen_on_conversation(DateTime.now.utc, assignee?)
  end

  def unread
    last_incoming_message = @conversation.messages.incoming.last
    last_seen_at = last_incoming_message.created_at - 1.second if last_incoming_message.present?
    update_last_seen_on_conversation(last_seen_at, true)
  end

  def custom_attributes
    @conversation.custom_attributes = params.permit(custom_attributes: {})[:custom_attributes]
    @conversation.save!
  end

  def destroy
    authorize @conversation, :destroy?
    ::DeleteObjectJob.perform_later(@conversation, Current.user, request.ip)
    head :ok
  end

  # Move all messages from current conversation to a target conversation within the same account (and inbox)
  def merge_messages
    authorize @conversation, :update?

    target_display_id = params[:target_id]
    render json: { error: 'target_id param missing' }, status: :unprocessable_entity and return if target_display_id.blank?

    target_conversation = Current.account.conversations.find_by!(display_id: target_display_id)
    authorize target_conversation, :update?

    if target_conversation.id == @conversation.id
      render json: { error: 'Source and target conversations are the same' }, status: :unprocessable_entity and return
    end

    if target_conversation.inbox_id != @conversation.inbox_id
      render json: { error: 'Conversations belong to different inboxes' }, status: :unprocessable_entity and return
    end

    moved_count = 0
    source_id = @conversation.display_id

    ActiveRecord::Base.transaction do
      Message.where(conversation_id: @conversation.id).find_each do |message|
        message.update!(conversation_id: target_conversation.id)
        moved_count += 1
      end

      # Also move attachments if they reference conversation_id
      Attachment.where(message_id: Message.where(conversation_id: target_conversation.id).select(:id))

      target_conversation.update!(updated_at: Time.current)

      # Delete the source conversation after moving all messages
      @conversation.destroy!
    end

    render json: {
      payload: {
        source_id: source_id,
        target_id: target_conversation.display_id,
        moved_count: moved_count
      }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Target conversation not found' }, status: :not_found
  end

  # POST /api/v1/accounts/:account_id/conversations/:id/whatsapp_call_recording
  # Upload WhatsApp call recording from browser
  def whatsapp_call_recording
    call_id = params[:call_id]
    recording_file = params[:recording]
    duration = params[:duration]&.to_i

    Rails.logger.info '[WHATSAPP_CALLS] [UPLOAD_RECORDING] =========================================='
    Rails.logger.info '[WHATSAPP_CALLS] [UPLOAD_RECORDING] Recording upload request received'
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] conversation_id=#{@conversation.id}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] call_id=#{call_id}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] file present=#{recording_file.present?}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] file size=#{recording_file&.size} bytes"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] duration=#{duration}s"
    Rails.logger.info '[WHATSAPP_CALLS] [UPLOAD_RECORDING] =========================================='

    return render json: { error: 'No recording file provided' }, status: :unprocessable_entity if recording_file.blank?

    return render json: { error: 'No call_id provided' }, status: :unprocessable_entity if call_id.blank?

    # Find WhatsappCall record
    whatsapp_call = WhatsappCall.find_by(call_id: call_id, conversation: @conversation)

    unless whatsapp_call
      Rails.logger.warn "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ❌ WhatsappCall record not found for call_id=#{call_id}, conversation_id=#{@conversation.id}"
      return render json: { error: 'Call not found' }, status: :not_found
    end

    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Found WhatsappCall record id=#{whatsapp_call.id}, status=#{whatsapp_call.status}"

    begin
      # Save recording file
      recording_path = save_recording_file(whatsapp_call, recording_file)

      # Update WhatsappCall with recording info (use provided duration if available)
      update_attrs = { recording_url: recording_path }
      update_attrs[:duration_seconds] = duration if duration&.positive?
      whatsapp_call.update!(update_attrs)

      # Create attachment message in conversation and get the updated message
      message = create_recording_message(whatsapp_call, recording_path)

      Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Recording saved successfully: #{recording_path}"
      Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Message ID: #{message&.id}"
      Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Attachments count: #{message&.attachments&.count || 0}"

      render json: {
        message: 'Recording uploaded successfully',
        recording_path: recording_path,
        message_id: message&.id,
        attachment_count: message&.attachments&.count || 0
      }, status: :ok
    rescue StandardError => e
      Rails.logger.error "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ❌ Failed to save recording: #{e.message}"
      Rails.logger.error "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ❌ Backtrace:\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  private

  def permitted_update_params
    # TODO: Move the other conversation attributes to this method and remove specific endpoints for each attribute
    params.permit(:priority)
  end

  def attachment_params
    params.permit(:page)
  end

  def update_last_seen_on_conversation(last_seen_at, update_assignee)
    updates = { agent_last_seen_at: last_seen_at }
    updates[:assignee_last_seen_at] = last_seen_at if update_assignee.present?

    # rubocop:disable Rails/SkipsModelValidations
    @conversation.update_columns(updates)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def should_update_last_seen?
    # Update if at least one relevant timestamp is older than 1 hour or not set
    # This prevents redundant DB writes when agents repeatedly view the same conversation
    agent_needs_update = @conversation.agent_last_seen_at.blank? || @conversation.agent_last_seen_at < 1.hour.ago
    return agent_needs_update unless assignee?

    # For assignees, check both timestamps - update if either is old
    assignee_needs_update = @conversation.assignee_last_seen_at.blank? || @conversation.assignee_last_seen_at < 1.hour.ago
    agent_needs_update || assignee_needs_update
  end

  def set_conversation_status
    @conversation.status = params[:status]
    @conversation.snoozed_until = parse_date_time(params[:snoozed_until].to_s) if params[:snoozed_until]
  end

  def assign_conversation
    @conversation.assignee = current_user
    @conversation.save!
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:id])
    authorize @conversation, :show?
  end

  def inbox
    return if params[:inbox_id].blank?

    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def contact
    return if params[:contact_id].blank?

    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def contact_inbox
    @contact_inbox = build_contact_inbox

    # fallback for the old case where we do look up only using source id
    # In future we need to change this and make sure we do look up on combination of inbox_id and source_id
    # and deprecate the support of passing only source_id as the param
    @contact_inbox ||= ::ContactInbox.find_by!(source_id: params[:source_id])
    authorize @contact_inbox.inbox, :show?
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'source_id should be unique' }, status: :unprocessable_entity
  end

  def build_contact_inbox
    return if @inbox.blank? || @contact.blank?

    ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: params[:source_id],
      hmac_verified: hmac_verified?
    ).perform
  end

  def set_conversation_for_recording
    @conversation = Current.account.conversations.find_by!(display_id: params[:id])
    authorize @conversation, :show?  # User must have access to the conversation
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conversation not found' }, status: :not_found
  end

  def conversation_finder
    @conversation_finder ||= ConversationFinder.new(Current.user, params)
  end

  def assignee?
    @conversation.assignee_id? && Current.user == @conversation.assignee
  end

  def save_recording_file(whatsapp_call, recording_file)
    # Create storage directory if it doesn't exist
    storage_dir = Rails.root.join('storage', 'whatsapp_call_recordings', whatsapp_call.account_id.to_s)
    FileUtils.mkdir_p(storage_dir)

    # Generate filename
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    filename = "call_#{whatsapp_call.id}_#{timestamp}.webm"
    file_path = storage_dir.join(filename)

    # Save file
    File.binwrite(file_path, recording_file.read)

    file_path.to_s
  end

  def create_recording_message(whatsapp_call, recording_path)
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] Looking for call_completed message for call_id=#{whatsapp_call.call_id}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] Conversation: #{whatsapp_call.conversation_id}, Account: #{whatsapp_call.account_id}"

    # Try to find existing call message (call_completed) for this call
    # Retry multiple times in case the terminate service is still creating the message
    # This handles the race condition where upload arrives before terminate completes
    call_message = nil
    max_retries = 15  # Aumentado de 5 a 15
    retry_delay = 0.7 # seconds (total: ~10.5 segundos)

    max_retries.times do |attempt|
      call_message = whatsapp_call.conversation.messages
                                  .where(content_type: :voice_call, call_status: :completed)
                                  .where.not(call_metadata: nil)
                                  .where("call_metadata->>'call_id' = ?", whatsapp_call.call_id)
                                  .order(created_at: :desc)
                                  .first

      if call_message
        Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Found call_completed message id=#{call_message.id} on attempt #{attempt + 1}"
        break
      end

      if attempt < max_retries - 1
        Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ⏳ Message not found yet (attempt #{attempt + 1}/#{max_retries}), waiting #{retry_delay}s..."
        sleep(retry_delay)
      else
        Rails.logger.warn "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ⚠️ Message not found after #{max_retries} attempts"
      end
    end

    if call_message
      Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Using existing call_completed message id=#{call_message.id}"
    else
      Rails.logger.warn '[WHATSAPP_CALLS] [UPLOAD_RECORDING] ⚠️ No call_completed message found after retries, creating new one'
      Rails.logger.warn '[WHATSAPP_CALLS] [UPLOAD_RECORDING] This may indicate a race condition - terminate may not have completed'
      duration_text = whatsapp_call.duration_formatted || '00:00'
      message_params = {
        content: "📞 Call Recording (#{duration_text})",
        account_id: whatsapp_call.account_id,
        inbox_id: whatsapp_call.conversation.inbox_id,
        conversation_id: whatsapp_call.conversation_id,
        message_type: :activity,
        content_type: :voice_call,
        call_status: :completed,
        call_duration: whatsapp_call.duration_seconds || 0,
        call_metadata: {
          call_id: whatsapp_call.call_id,
          whatsapp_call_sid: whatsapp_call.call_id,
          call_direction: whatsapp_call.direction || 'outbound',
          initiated_at: whatsapp_call.initiated_at&.to_i,
          connected_at: whatsapp_call.connected_at&.to_i,
          ended_at: whatsapp_call.ended_at&.to_i,
          recording_duration: whatsapp_call.duration_seconds || 0
        },
        private: false,
        sender: nil
      }
      call_message = whatsapp_call.conversation.messages.create!(message_params)
      Rails.logger.info "[WHATSAPP_CALLS] Created new call message id=#{call_message.id}"
    end

    # Attach recording file to the call message
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] 📎 Attaching recording file to message id=#{call_message.id}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] File path: #{recording_path}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] File exists: #{File.exist?(recording_path)}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] File size: #{File.exist?(recording_path) ? File.size(recording_path) : 'N/A'} bytes"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] Duration: #{whatsapp_call.duration_seconds}s"

    attachment = call_message.attachments.new(
      file_type: :audio,
      account_id: whatsapp_call.account_id,
      meta: { duration: whatsapp_call.duration_seconds }
    )

    # Save attachment first
    attachment.save!
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Attachment record created id=#{attachment.id} with duration=#{attachment.meta['duration']}s"

    # Now attach file using ActiveStorage
    File.open(recording_path, 'rb') do |file|
      attachment.file.attach(
        io: file,
        filename: File.basename(recording_path),
        content_type: 'audio/webm'
      )
    end

    # Verify file attached
    unless attachment.file.attached?
      Rails.logger.error "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ❌ Failed to attach file to attachment id=#{attachment.id}"
      raise 'Failed to attach recording file'
    end

    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ File attached to attachment id=#{attachment.id}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] File details: content_type=#{attachment.file.content_type}, byte_size=#{attachment.file.byte_size}"
    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] Blob: id=#{attachment.file.blob.id}, key=#{attachment.file.blob.key}"

    # Test attachment data generation
    Rails.logger.info "[WHATSAPP_CALLS] Testing attachment.file_url: #{attachment.file_url}"
    attachment_event_data = attachment.push_event_data
    Rails.logger.info "[WHATSAPP_CALLS] Attachment push_event_data: #{attachment_event_data.inspect}"

    # Reload message to include the attachment
    call_message.reload
    Rails.logger.info "[WHATSAPP_CALLS] Message reloaded with attachments count: #{call_message.attachments.count}"

    # Check message push_event_data
    message_event_data = call_message.push_event_data
    Rails.logger.info "[WHATSAPP_CALLS] Message push_event_data keys: #{message_event_data.keys.inspect}"
    if message_event_data[:attachments]
      Rails.logger.info "[WHATSAPP_CALLS] Attachments in message data (count: #{message_event_data[:attachments].length})"
      message_event_data[:attachments].each_with_index do |att_data, idx|
        Rails.logger.info "[WHATSAPP_CALLS]   Attachment #{idx + 1}: #{att_data.inspect}"
      end
    else
      Rails.logger.error '[WHATSAPP_CALLS] NO ATTACHMENTS IN MESSAGE PUSH_EVENT_DATA!'
    end

    # Force broadcast immediately - file is already attached
    # We dispatch the update event synchronously since ActiveStorage blob is already saved
    Rails.logger.info '[WHATSAPP_CALLS] [UPLOAD_RECORDING] 📡 Dispatching message.updated event'
    Rails.configuration.dispatcher.dispatch(
      'message.updated',
      Time.zone.now,
      message: call_message,
      performed_by: nil
    )

    Rails.logger.info "[WHATSAPP_CALLS] [UPLOAD_RECORDING] ✅ Broadcast dispatched for message id=#{call_message.id}"
    Rails.logger.info '[WHATSAPP_CALLS] [UPLOAD_RECORDING] =========================================='

    call_message
  end
end

Api::V1::Accounts::ConversationsController.prepend_mod_with('Api::V1::Accounts::ConversationsController')
