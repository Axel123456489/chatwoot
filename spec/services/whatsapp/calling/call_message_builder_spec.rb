# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Calling::CallMessageBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:whatsapp_call) do
    WhatsappCall.create!(
      account: account,
      conversation: conversation,
      call_id: 'test-call-123',
      whatsapp_call_sid: 'whatsapp-sid-123',
      call_direction: 'inbound',
      from_number: '+1234567890',
      to_number: '+0987654321',
      call_status: 'ringing',
      initiated_at: Time.current
    )
  end

  let(:builder) do
    described_class.new(
      conversation: conversation,
      whatsapp_call: whatsapp_call
    )
  end

  describe '#create_initiated_message' do
    it 'creates a message with initiated status' do
      message = builder.create_initiated_message

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
      expect(message.call_status).to eq('initiated')
      expect(message.content).to eq('Call initiated')
    end

    it 'sets correct message_type based on call direction' do
      whatsapp_call.call_direction = 'inbound'
      message = builder.create_initiated_message
      expect(message.message_type).to eq('incoming')

      whatsapp_call.call_direction = 'outbound'
      message = builder.create_initiated_message
      expect(message.message_type).to eq('outgoing')
    end

    it 'stores call metadata' do
      message = builder.create_initiated_message

      expect(message.call_id).to eq('test-call-123')
      expect(message.call_direction).to eq('inbound')
      expect(message.whatsapp_call_sid).to eq('whatsapp-sid-123')
      expect(message.initiated_at).to be_present
    end
  end

  describe '#create_connected_message' do
    before do
      whatsapp_call.update!(
        call_status: 'connected',
        connected_at: Time.current
      )
    end

    it 'creates a message with connected status' do
      message = builder.create_connected_message

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
      expect(message.call_status).to eq('connected')
      expect(message.content).to eq('Call connected')
    end

    it 'stores connection timestamp' do
      message = builder.create_connected_message
      expect(message.connected_at).to be_present
    end
  end

  describe '#create_completed_message' do
    let(:attachment) do
      instance_double(
        Attachment,
        id: 1,
        file_type: 'audio',
        data_url: 'https://example.com/recording.mp3',
        push_event_data: { id: 1, file_type: 'audio' }
      )
    end

    before do
      whatsapp_call.update!(
        call_status: 'completed',
        connected_at: 2.minutes.ago,
        ended_at: Time.current,
        recording_url: 'https://example.com/recording.mp3',
        recording_duration: 120
      )
    end

    it 'creates a message with completed status' do
      message = builder.create_completed_message(attachment)

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
      expect(message.call_status).to eq('completed')
      expect(message.content).to eq('Call completed (2m 0s)')
    end

    it 'calculates call duration automatically if not provided' do
      whatsapp_call.update!(call_duration: nil)
      message = builder.create_completed_message(attachment)

      expect(message.call_duration).to eq(120)
    end

    it 'stores recording information' do
      message = builder.create_completed_message(attachment)

      expect(message.recording_url).to eq('https://example.com/recording.mp3')
      expect(message.recording_duration).to eq(120)
    end

    it 'works without attachment' do
      message = builder.create_completed_message(nil)

      expect(message).to be_persisted
      expect(message.call_status).to eq('completed')
    end
  end

  describe '#create_failed_message' do
    it 'creates a message with failed status' do
      message = builder.create_failed_message(
        reason: 'rejected',
        error_code: nil,
        error_message: nil
      )

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
      expect(message.call_status).to eq('rejected')
      expect(message.content).to eq('Call rejected')
    end

    it 'handles different failure reasons' do
      %w[rejected missed cancelled busy no_connection failed].each do |reason|
        message = builder.create_failed_message(reason: reason)
        expect(message.call_status).to eq(reason)
      end
    end

    it 'stores error information when provided' do
      message = builder.create_failed_message(
        reason: 'failed',
        error_code: 'CONNECTION_ERROR',
        error_message: 'Network timeout'
      )

      expect(message.error_code).to eq('CONNECTION_ERROR')
      expect(message.error_message).to eq('Network timeout')
    end

    it 'records ended_at timestamp' do
      message = builder.create_failed_message(reason: 'rejected')
      expect(message.ended_at).to be_present
    end
  end

  describe '#create_meta_error_message' do
    let(:meta_response) do
      {
        'error' => {
          'message' => 'Permission denied',
          'type' => 'OAuthException',
          'code' => 200,
          'error_subcode' => 2_494_055
        }
      }
    end

    it 'creates a message with Meta error status' do
      message = builder.create_meta_error_message(
        error_code: 'PERMISSION_DENIED',
        error_message: 'Not authorized to make calls',
        meta_response: meta_response
      )

      expect(message).to be_persisted
      expect(message.content_type).to eq('voice_call')
      expect(message.call_status).to eq('unauthorized')
      expect(message.content).to eq('Call failed: Not authorized')
    end

    it 'maps different error codes correctly' do
      error_mappings = {
        'PERMISSION_DENIED' => 'unauthorized',
        'INSUFFICIENT_BALANCE' => 'no_balance',
        'CALLING_NOT_ENABLED' => 'not_enabled',
        'RATE_LIMIT_HIT' => 'rate_limit',
        'INVALID_PARAMETER' => 'invalid'
      }

      error_mappings.each do |error_code, expected_status|
        message = builder.create_meta_error_message(
          error_code: error_code,
          error_message: 'Test error',
          meta_response: meta_response
        )
        expect(message.call_status).to eq(expected_status)
      end
    end

    it 'stores error information' do
      message = builder.create_meta_error_message(
        error_code: 'PERMISSION_DENIED',
        error_message: 'Not authorized',
        meta_response: meta_response
      )

      expect(message.error_code).to eq('PERMISSION_DENIED')
      expect(message.error_message).to eq('Not authorized')
      expect(message.meta_response).to eq(meta_response)
    end

    it 'records ended_at timestamp' do
      message = builder.create_meta_error_message(
        error_code: 'PERMISSION_DENIED',
        error_message: 'Not authorized',
        meta_response: meta_response
      )
      expect(message.ended_at).to be_present
    end
  end

  describe 'private methods' do
    describe '#determine_message_type' do
      it 'returns incoming for inbound calls' do
        whatsapp_call.call_direction = 'inbound'
        expect(builder.send(:determine_message_type)).to eq('incoming')
      end

      it 'returns outgoing for outbound calls' do
        whatsapp_call.call_direction = 'outbound'
        expect(builder.send(:determine_message_type)).to eq('outgoing')
      end

      it 'defaults to incoming for unknown direction' do
        whatsapp_call.call_direction = 'unknown'
        expect(builder.send(:determine_message_type)).to eq('incoming')
      end
    end

    describe '#calculate_call_duration' do
      it 'calculates duration from timestamps' do
        whatsapp_call.update!(
          connected_at: 2.minutes.ago,
          ended_at: Time.current
        )
        expect(builder.send(:calculate_call_duration)).to eq(120)
      end

      it 'uses existing call_duration if available' do
        whatsapp_call.update!(call_duration: 150)
        expect(builder.send(:calculate_call_duration)).to eq(150)
      end

      it 'returns nil if timestamps are missing' do
        whatsapp_call.update!(connected_at: nil, ended_at: nil, call_duration: nil)
        expect(builder.send(:calculate_call_duration)).to be_nil
      end
    end
  end
end
