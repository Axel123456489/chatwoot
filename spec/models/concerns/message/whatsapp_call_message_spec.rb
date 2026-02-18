# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message::WhatsappCallMessage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:message) do
    create(:message,
           account: account,
           inbox: inbox,
           conversation: conversation,
           content_type: 'voice_call',
           message_type: 'incoming')
  end

  describe 'enums' do
    it 'defines call_status enum with correct values' do
      expect(Message.call_statuses).to include(
        'initiated' => 0,
        'connected' => 1,
        'completed' => 2,
        'rejected' => 3,
        'missed' => 4,
        'cancelled' => 5,
        'busy' => 6,
        'no_connection' => 7,
        'failed' => 8,
        'unauthorized' => 9,
        'no_balance' => 10,
        'not_enabled' => 11,
        'rate_limit' => 12,
        'invalid' => 13,
        'other_meta_error' => 14
      )
    end
  end

  describe 'store accessors' do
    it 'provides access to call_metadata fields' do
      message.call_id = 'test-call-123'
      message.call_direction = 'inbound'
      message.whatsapp_call_sid = 'whatsapp-sid-123'
      message.initiated_at = Time.current
      message.connected_at = 5.seconds.from_now
      message.ended_at = 2.minutes.from_now
      message.recording_url = 'https://example.com/recording.mp3'
      message.recording_duration = 115
      message.error_code = 'ERROR_CODE'
      message.error_message = 'Something went wrong'

      expect(message.call_id).to eq('test-call-123')
      expect(message.call_direction).to eq('inbound')
      expect(message.whatsapp_call_sid).to eq('whatsapp-sid-123')
      expect(message.initiated_at).to be_present
      expect(message.connected_at).to be_present
      expect(message.ended_at).to be_present
      expect(message.recording_url).to eq('https://example.com/recording.mp3')
      expect(message.recording_duration).to eq(115)
      expect(message.error_code).to eq('ERROR_CODE')
      expect(message.error_message).to eq('Something went wrong')
    end
  end

  describe '#voice_call?' do
    it 'returns true for voice_call content_type' do
      expect(message.voice_call?).to be true
    end

    it 'returns false for other content_types' do
      message.content_type = 'text'
      expect(message.voice_call?).to be false
    end
  end

  describe '#call_successful?' do
    it 'returns true for successful statuses' do
      %w[initiated connected completed].each do |status|
        message.call_status = status
        expect(message.call_successful?).to be true
      end
    end

    it 'returns false for failed statuses' do
      %w[rejected missed cancelled busy no_connection failed].each do |status|
        message.call_status = status
        expect(message.call_successful?).to be false
      end
    end
  end

  describe '#call_failed?' do
    it 'returns true for failed statuses' do
      %w[rejected missed cancelled busy no_connection failed].each do |status|
        message.call_status = status
        expect(message.call_failed?).to be true
      end
    end

    it 'returns false for successful statuses' do
      %w[initiated connected completed].each do |status|
        message.call_status = status
        expect(message.call_failed?).to be false
      end
    end
  end

  describe '#call_meta_error?' do
    it 'returns true for Meta error statuses' do
      %w[unauthorized no_balance not_enabled rate_limit invalid other_meta_error].each do |status|
        message.call_status = status
        expect(message.call_meta_error?).to be true
      end
    end

    it 'returns false for non-error statuses' do
      %w[initiated connected completed rejected].each do |status|
        message.call_status = status
        expect(message.call_meta_error?).to be false
      end
    end
  end

  describe '#has_recording?' do
    it 'returns true when recording_url is present' do
      message.recording_url = 'https://example.com/recording.mp3'
      expect(message.has_recording?).to be true
    end

    it 'returns false when recording_url is nil' do
      message.recording_url = nil
      expect(message.has_recording?).to be false
    end

    it 'returns false when recording_url is empty' do
      message.recording_url = ''
      expect(message.has_recording?).to be false
    end
  end

  describe '#formatted_call_duration' do
    it 'formats duration in minutes and seconds' do
      message.call_duration = 125
      expect(message.formatted_call_duration).to eq('2m 5s')
    end

    it 'handles durations less than a minute' do
      message.call_duration = 45
      expect(message.formatted_call_duration).to eq('45s')
    end

    it 'handles durations over an hour' do
      message.call_duration = 3665
      expect(message.formatted_call_duration).to eq('61m 5s')
    end

    it 'returns nil when duration is nil' do
      message.call_duration = nil
      expect(message.formatted_call_duration).to be_nil
    end

    it 'returns nil when duration is zero' do
      message.call_duration = 0
      expect(message.formatted_call_duration).to be_nil
    end
  end

  describe '#call_status_icon' do
    it 'returns correct icon for each status' do
      icons = {
        'initiated' => 'phone',
        'connected' => 'phone-call',
        'completed' => 'phone-call',
        'rejected' => 'phone-missed',
        'missed' => 'phone-missed',
        'cancelled' => 'phone-off',
        'busy' => 'phone-outgoing',
        'no_connection' => 'wifi-off',
        'failed' => 'alert-circle',
        'unauthorized' => 'alert-circle',
        'no_balance' => 'credit-card',
        'not_enabled' => 'x-circle',
        'rate_limit' => 'clock',
        'invalid' => 'alert-triangle'
      }

      icons.each do |status, icon|
        message.call_status = status
        expect(message.call_status_icon).to eq(icon)
      end
    end
  end

  describe '#call_status_message' do
    it 'returns correct message for successful statuses' do
      message.call_status = 'initiated'
      expect(message.call_status_message).to eq('Call initiated')

      message.call_status = 'connected'
      expect(message.call_status_message).to eq('Call connected')

      message.call_status = 'completed'
      message.call_duration = 125
      expect(message.call_status_message).to eq('Call completed (2m 5s)')
    end

    it 'returns correct message for failed statuses' do
      message.call_status = 'rejected'
      expect(message.call_status_message).to eq('Call rejected')

      message.call_status = 'missed'
      expect(message.call_status_message).to eq('Call missed')
    end

    it 'returns correct message for Meta errors' do
      message.call_status = 'unauthorized'
      expect(message.call_status_message).to eq('Call failed: Not authorized')

      message.call_status = 'no_balance'
      expect(message.call_status_message).to eq('Call failed: Insufficient balance')
    end
  end

  describe '.meta_error_to_call_status' do
    it 'maps Meta error codes to call statuses' do
      expect(Message.meta_error_to_call_status('PERMISSION_DENIED')).to eq('unauthorized')
      expect(Message.meta_error_to_call_status('INSUFFICIENT_BALANCE')).to eq('no_balance')
      expect(Message.meta_error_to_call_status('CALLING_NOT_ENABLED')).to eq('not_enabled')
      expect(Message.meta_error_to_call_status('RATE_LIMIT_HIT')).to eq('rate_limit')
      expect(Message.meta_error_to_call_status('INVALID_PARAMETER')).to eq('invalid')
    end

    it 'returns other_meta_error for unknown codes' do
      expect(Message.meta_error_to_call_status('UNKNOWN_ERROR')).to eq('other_meta_error')
    end

    it 'returns other_meta_error for nil' do
      expect(Message.meta_error_to_call_status(nil)).to eq('other_meta_error')
    end
  end

  describe '.call_successful_statuses' do
    it 'returns array of successful status names' do
      expect(Message.call_successful_statuses).to eq(%w[initiated connected completed])
    end
  end

  describe '.call_failed_statuses' do
    it 'returns array of failed status names' do
      expect(Message.call_failed_statuses).to eq(%w[rejected missed cancelled busy no_connection failed])
    end
  end
end
