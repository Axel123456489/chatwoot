# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Calling::CallTerminateService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           calling_enabled: true,
           calling_config: {
             'recording_enabled' => true
           })
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, identifier: 'test-call-123') }

  let!(:whatsapp_call) do
    WhatsappCall.create!(
      account: account,
      conversation: conversation,
      call_id: 'test-call-123',
      whatsapp_call_sid: 'whatsapp-sid-123',
      call_direction: 'inbound',
      from_number: '+1234567890',
      to_number: '+0987654321',
      call_status: 'connected',
      initiated_at: 2.minutes.ago,
      connected_at: 2.minutes.ago
    )
  end

  let(:call_data) do
    {
      'id' => 'test-call-123',
      'status' => 'COMPLETED',
      'duration' => 120,
      'start_time' => (2.minutes.ago).iso8601,
      'end_time' => Time.current.iso8601
    }
  end

  let(:service) do
    described_class.new(
      account: account,
      inbox: inbox,
      call_id: 'test-call-123',
      call_data: call_data
    )
  end

  before do
    # Mock recording service
    allow_any_instance_of(Whatsapp::Calling::RecordingService).to receive(:stop).and_return(
      success: true,
      recording_url: 'https://example.com/recording.mp3',
      duration: 120
    )
  end

  describe '#perform' do
    context 'when call is successful' do
      it 'creates a completed message' do
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content_type).to eq('voice_call')
        expect(message.call_status).to eq('completed')
        expect(message.content).to include('Call completed')
      end

      it 'updates WhatsappCall record' do
        service.perform

        whatsapp_call.reload
        expect(whatsapp_call.call_status).to eq('completed')
        expect(whatsapp_call.ended_at).to be_present
        expect(whatsapp_call.call_duration).to eq(120)
      end

      it 'stops recording if enabled' do
        recording_service = instance_double(Whatsapp::Calling::RecordingService)
        allow(Whatsapp::Calling::RecordingService).to receive(:new).and_return(recording_service)
        expect(recording_service).to receive(:stop).and_return(
          success: true,
          recording_url: 'https://example.com/recording.mp3',
          duration: 120
        )

        service.perform
      end

      it 'creates recording attachment when recording is available' do
        allow_any_instance_of(Whatsapp::Calling::RecordingService).to receive(:stop).and_return(
          success: true,
          recording_url: 'https://example.com/recording.mp3',
          duration: 120
        )

        service.perform

        message = Message.last
        expect(message.recording_url).to eq('https://example.com/recording.mp3')
        expect(message.recording_duration).to eq(120)
      end
    end

    context 'when call failed' do
      let(:call_data) do
        {
          'id' => 'test-call-123',
          'status' => 'FAILED',
          'duration' => 0,
          'start_time' => (1.minute.ago).iso8601,
          'end_time' => Time.current.iso8601,
          'error_code' => 'NO_ANSWER',
          'error_message' => 'The call was not answered'
        }
      end

      before do
        whatsapp_call.update!(call_status: 'initiated', connected_at: nil)
      end

      it 'creates a failed message' do
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content_type).to eq('voice_call')
        expect(message.call_status).to eq('missed')
        expect(message.content).to include('Call missed')
      end

      it 'determines correct failure reason' do
        call_data['status'] = 'REJECTED'
        service.perform

        message = Message.last
        expect(message.call_status).to eq('rejected')
      end

      it 'does not create recording attachment' do
        service.perform

        message = Message.last
        expect(message.recording_url).to be_nil
      end
    end

    context 'when conversation is not found' do
      let(:service) do
        described_class.new(
          account: account,
          inbox: inbox,
          call_id: 'nonexistent-call',
          call_data: call_data
        )
      end

      it 'logs warning and returns nil' do
        expect(Rails.logger).to receive(:warn).with(/Conversation not found/)
        expect(service.perform).to be_nil
      end
    end

    context 'when WhatsappCall record is not found' do
      before do
        whatsapp_call.destroy
      end

      it 'logs warning and returns nil' do
        expect(Rails.logger).to receive(:warn).with(/WhatsappCall record not found/)
        expect(service.perform).to be_nil
      end
    end

    context 'when recording stop fails' do
      before do
        allow_any_instance_of(Whatsapp::Calling::RecordingService).to receive(:stop).and_return(
          success: false,
          error: 'Recording service unavailable'
        )
      end

      it 'still creates completed message without recording' do
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.call_status).to eq('completed')
        expect(message.recording_url).to be_nil
      end
    end
  end

  describe '#determine_failure_reason' do
    it 'maps WhatsApp statuses to failure reasons' do
      expect(service.send(:determine_failure_reason, 'REJECTED')).to eq('rejected')
      expect(service.send(:determine_failure_reason, 'BUSY')).to eq('busy')
      expect(service.send(:determine_failure_reason, 'NO_ANSWER')).to eq('missed')
      expect(service.send(:determine_failure_reason, 'FAILED')).to eq('failed')
    end

    it 'maps based on connected_at for ambiguous statuses' do
      whatsapp_call.update!(connected_at: nil)
      expect(service.send(:determine_failure_reason, 'COMPLETED')).to eq('missed')

      whatsapp_call.update!(connected_at: Time.current)
      expect(service.send(:determine_failure_reason, 'COMPLETED')).to eq('cancelled')
    end

    it 'returns failed for unknown statuses' do
      expect(service.send(:determine_failure_reason, 'UNKNOWN')).to eq('failed')
    end
  end
end
