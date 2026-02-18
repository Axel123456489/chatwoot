# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'WhatsApp Call Message Lifecycle', type: :integration do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           calling_enabled: true,
           calling_config: {
             'recording_enabled' => true,
             'media_server_url' => 'https://media.example.com/webrtc'
           })
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account, phone_number: '+1234567890') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

  before do
    # Mock external services
    allow_any_instance_of(Whatsapp::Calling::RecordingService).to receive(:stop).and_return(
      success: true,
      recording_url: 'https://example.com/recording.mp3',
      duration: 120
    )
  end

  describe 'Successful call flow' do
    it 'creates proper message timeline from initiation to completion' do
      # 1. Inbound call arrives - creates initiated message
      call_data = {
        'id' => 'call-12345',
        'from' => '+1234567890',
        'to' => '+0987654321',
        'direction' => 'USER_INITIATED',
        'session' => { 'sdp' => 'v=0...' }
      }

      builder = Whatsapp::Calling::InboundCallBuilder.new(
        account: account,
        inbox: inbox,
        call_data: call_data,
        metadata: {}
      )

      expect { builder.perform }.to change(Message, :count).by(1)
                                .and change(WhatsappCall, :count).by(1)

      conversation = Conversation.find_by(identifier: 'call-12345')
      initiated_message = conversation.messages.last

      expect(initiated_message.content_type).to eq('voice_call')
      expect(initiated_message.call_status).to eq('initiated')
      expect(initiated_message.message_type).to eq('incoming')
      expect(initiated_message.content).to eq('Call initiated')

      whatsapp_call = WhatsappCall.find_by(call_id: 'call-12345')
      expect(whatsapp_call.call_status).to eq('ringing')

      # 2. Call is answered - creates connected message
      whatsapp_call.update!(
        call_status: 'connected',
        connected_at: Time.current
      )

      connect_service = Whatsapp::Calling::BusinessCallConnectService.new(
        account: account,
        inbox: inbox,
        call_data: {
          'id' => 'call-12345',
          'session' => { 'sdp' => 'v=0...' }
        },
        metadata: { 'conversation_id' => conversation.id }
      )

      expect { connect_service.perform }.to change { conversation.messages.count }.by(1)

      connected_message = conversation.messages.last
      expect(connected_message.call_status).to eq('connected')
      expect(connected_message.content).to eq('Call connected')

      whatsapp_call.reload
      expect(whatsapp_call.call_status).to eq('connected')

      # 3. Call ends successfully - creates completed message with recording
      terminate_service = Whatsapp::Calling::CallTerminateService.new(
        account: account,
        inbox: inbox,
        call_id: 'call-12345',
        call_data: {
          'id' => 'call-12345',
          'status' => 'COMPLETED',
          'duration' => 120
        }
      )

      expect { terminate_service.perform }.to change { conversation.messages.count }.by(1)

      completed_message = conversation.messages.last
      expect(completed_message.call_status).to eq('completed')
      expect(completed_message.content).to include('Call completed')
      expect(completed_message.call_duration).to eq(120)
      expect(completed_message.recording_url).to eq('https://example.com/recording.mp3')

      whatsapp_call.reload
      expect(whatsapp_call.call_status).to eq('completed')

      # Verify complete timeline
      all_messages = conversation.messages.where(content_type: 'voice_call').order(:created_at)
      expect(all_messages.count).to eq(3)
      expect(all_messages.pluck(:call_status)).to eq(%w[initiated connected completed])
    end
  end

  describe 'Failed call flow' do
    it 'handles rejected call properly' do
      # 1. Inbound call arrives
      call_data = {
        'id' => 'call-67890',
        'from' => '+1234567890',
        'to' => '+0987654321',
        'direction' => 'USER_INITIATED',
        'session' => { 'sdp' => 'v=0...' }
      }

      builder = Whatsapp::Calling::InboundCallBuilder.new(
        account: account,
        inbox: inbox,
        call_data: call_data,
        metadata: {}
      )

      builder.perform

      conversation = Conversation.find_by(identifier: 'call-67890')
      whatsapp_call = WhatsappCall.find_by(call_id: 'call-67890')

      # 2. Call is rejected by user
      status_service = Whatsapp::Calling::CallStatusService.new(
        account: account,
        inbox: inbox,
        status_data: {
          'id' => 'call-67890',
          'status' => 'REJECTED'
        },
        metadata: {}
      )

      expect { status_service.perform }.to change { conversation.messages.count }.by(1)

      rejected_message = conversation.messages.last
      expect(rejected_message.call_status).to eq('rejected')
      expect(rejected_message.content).to eq('Call rejected')

      whatsapp_call.reload
      expect(whatsapp_call.call_status).to eq('rejected')

      # Verify timeline
      all_messages = conversation.messages.where(content_type: 'voice_call').order(:created_at)
      expect(all_messages.count).to eq(2)
      expect(all_messages.pluck(:call_status)).to eq(%w[initiated rejected])
    end

    it 'handles missed call properly' do
      call_data = {
        'id' => 'call-missed',
        'from' => '+1234567890',
        'to' => '+0987654321',
        'direction' => 'USER_INITIATED',
        'session' => { 'sdp' => 'v=0...' }
      }

      builder = Whatsapp::Calling::InboundCallBuilder.new(
        account: account,
        inbox: inbox,
        call_data: call_data,
        metadata: {}
      )

      builder.perform

      conversation = Conversation.find_by(identifier: 'call-missed')

      # Call is missed (not answered)
      status_service = Whatsapp::Calling::CallStatusService.new(
        account: account,
        inbox: inbox,
        status_data: {
          'id' => 'call-missed',
          'status' => 'MISSED'
        },
        metadata: {}
      )

      expect { status_service.perform }.to change { conversation.messages.count }.by(1)

      missed_message = conversation.messages.last
      expect(missed_message.call_status).to eq('missed')
      expect(missed_message.content).to eq('Call missed')
    end
  end

  describe 'Meta API error flow' do
    it 'handles Meta API errors during call initiation' do
      conversation = create(:conversation, account: account, inbox: inbox)
      whatsapp_call = WhatsappCall.create!(
        account: account,
        conversation: conversation,
        call_id: 'call-error',
        whatsapp_call_sid: 'sid-error',
        call_direction: 'outbound',
        from_number: '+0987654321',
        to_number: '+1234567890',
        call_status: 'initiated',
        initiated_at: Time.current
      )

      meta_response = {
        'error' => {
          'message' => 'Insufficient balance',
          'type' => 'OAuthException',
          'code' => 200,
          'error_subcode' => 2_494_055
        }
      }

      builder = Whatsapp::Calling::CallMessageBuilder.new(
        conversation: conversation,
        whatsapp_call: whatsapp_call
      )

      expect do
        builder.create_meta_error_message(
          error_code: 'INSUFFICIENT_BALANCE',
          error_message: 'Not enough credits',
          meta_response: meta_response
        )
      end.to change { conversation.messages.count }.by(1)

      error_message = conversation.messages.last
      expect(error_message.call_status).to eq('no_balance')
      expect(error_message.content).to eq('Call failed: Insufficient balance')
      expect(error_message.error_code).to eq('INSUFFICIENT_BALANCE')
      expect(error_message.error_message).to eq('Not enough credits')
      expect(error_message.call_meta_error?).to be true
    end
  end

  describe 'Message serialization' do
    it 'includes call information in API response' do
      conversation = create(:conversation, account: account, inbox: inbox)
      message = create(:message,
                       account: account,
                       inbox: inbox,
                       conversation: conversation,
                       content_type: 'voice_call',
                       message_type: 'incoming',
                       content: 'Call completed',
                       call_status: :completed,
                       call_duration: 125)

      message.call_id = 'test-call'
      message.call_direction = 'inbound'
      message.recording_url = 'https://example.com/recording.mp3'
      message.recording_duration = 125
      message.save!

      # Simulate API serialization
      json = ApplicationController.renderer.render(
        partial: 'api/v1/models/message',
        formats: [:json],
        locals: { message: message }
      )

      parsed = JSON.parse(json)
      expect(parsed['content_type']).to eq('voice_call')
      expect(parsed['call_status']).to eq('completed')
      expect(parsed['call_duration']).to eq(125)
      expect(parsed['call_metadata']).to be_present
      expect(parsed['call_metadata']['call_id']).to eq('test-call')
      expect(parsed['call_metadata']['recording_url']).to eq('https://example.com/recording.mp3')
    end
  end
end
