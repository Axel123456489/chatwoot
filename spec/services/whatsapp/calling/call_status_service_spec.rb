# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Calling::CallStatusService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           calling_enabled: true)
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
      call_status: 'initiated',
      initiated_at: 1.minute.ago
    )
  end

  let(:status_data) do
    {
      'id' => 'test-call-123',
      'status' => 'REJECTED'
    }
  end

  let(:metadata) { {} }

  let(:service) do
    described_class.new(
      account: account,
      inbox: inbox,
      status_data: status_data,
      metadata: metadata
    )
  end

  describe '#perform' do
    context 'when status is a terminal failure' do
      it 'creates a failed message for REJECTED status' do
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content_type).to eq('voice_call')
        expect(message.call_status).to eq('rejected')
        expect(message.content).to include('Call rejected')
      end

      it 'creates a failed message for MISSED status' do
        status_data['status'] = 'MISSED'
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.call_status).to eq('missed')
      end

      it 'creates a failed message for CANCELLED status' do
        status_data['status'] = 'CANCELLED'
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.call_status).to eq('cancelled')
      end

      it 'creates a failed message for BUSY status' do
        status_data['status'] = 'BUSY'
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.call_status).to eq('busy')
      end

      it 'creates a failed message for FAILED status' do
        status_data['status'] = 'FAILED'
        expect { service.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.call_status).to eq('failed')
      end
    end

    context 'when status includes error information' do
      let(:status_data) do
        {
          'id' => 'test-call-123',
          'status' => 'FAILED',
          'error_code' => 'NETWORK_ERROR',
          'error_message' => 'Connection timeout'
        }
      end

      it 'stores error information in the message' do
        service.perform

        message = Message.last
        expect(message.error_code).to eq('NETWORK_ERROR')
        expect(message.error_message).to eq('Connection timeout')
      end

      it 'updates WhatsappCall with error information' do
        service.perform

        whatsapp_call.reload
        expect(whatsapp_call.error_code).to eq('NETWORK_ERROR')
        expect(whatsapp_call.error_message).to eq('Connection timeout')
      end
    end

    context 'when status is non-terminal' do
      it 'does not create a message for RINGING status' do
        status_data['status'] = 'RINGING'
        expect { service.perform }.not_to change(Message, :count)
      end

      it 'does not create a message for ACCEPTED status' do
        status_data['status'] = 'ACCEPTED'
        expect { service.perform }.not_to change(Message, :count)
      end

      it 'does not create a message for CONNECTED status' do
        status_data['status'] = 'CONNECTED'
        expect { service.perform }.not_to change(Message, :count)
      end
    end

    context 'when updating conversation status' do
      it 'updates conversation additional_attributes' do
        service.perform

        conversation.reload
        expect(conversation.additional_attributes['call_status']).to eq('rejected')
        expect(conversation.additional_attributes['status_updated_at']).to be_present
      end
    end

    context 'when updating WhatsappCall status' do
      it 'maps WhatsApp status to internal call_status' do
        service.perform

        whatsapp_call.reload
        expect(whatsapp_call.call_status).to eq('rejected')
      end

      it 'handles CANCELED spelling variation' do
        status_data['status'] = 'CANCELED'
        service.perform

        whatsapp_call.reload
        expect(whatsapp_call.call_status).to eq('cancelled')
      end
    end

    context 'when conversation is not found' do
      let(:service) do
        described_class.new(
          account: account,
          inbox: inbox,
          status_data: { 'id' => 'nonexistent-call', 'status' => 'REJECTED' },
          metadata: metadata
        )
      end

      it 'does not create a message' do
        expect { service.perform }.not_to change(Message, :count)
      end
    end

    context 'when WhatsappCall record is not found' do
      before do
        whatsapp_call.destroy
      end

      it 'does not create a message' do
        expect { service.perform }.not_to change(Message, :count)
      end
    end
  end

  describe '#map_whatsapp_status_to_call_status' do
    it 'maps WhatsApp statuses correctly' do
      expect(service.send(:map_whatsapp_status_to_call_status, 'RINGING')).to eq('initiated')
      expect(service.send(:map_whatsapp_status_to_call_status, 'ACCEPTED')).to eq('connected')
      expect(service.send(:map_whatsapp_status_to_call_status, 'CONNECTED')).to eq('connected')
      expect(service.send(:map_whatsapp_status_to_call_status, 'REJECTED')).to eq('rejected')
      expect(service.send(:map_whatsapp_status_to_call_status, 'MISSED')).to eq('missed')
      expect(service.send(:map_whatsapp_status_to_call_status, 'CANCELLED')).to eq('cancelled')
      expect(service.send(:map_whatsapp_status_to_call_status, 'CANCELED')).to eq('cancelled')
      expect(service.send(:map_whatsapp_status_to_call_status, 'BUSY')).to eq('busy')
      expect(service.send(:map_whatsapp_status_to_call_status, 'FAILED')).to eq('failed')
    end

    it 'defaults to failed for unknown statuses' do
      expect(service.send(:map_whatsapp_status_to_call_status, 'UNKNOWN')).to eq('failed')
    end
  end

  describe '#should_create_message?' do
    it 'returns true for terminal failure statuses' do
      %w[REJECTED MISSED CANCELLED CANCELED BUSY FAILED].each do |status|
        status_data['status'] = status
        expect(service.send(:should_create_message?)).to be true
      end
    end

    it 'returns false for non-terminal statuses' do
      %w[RINGING ACCEPTED CONNECTED].each do |status|
        status_data['status'] = status
        expect(service.send(:should_create_message?)).to be false
      end
    end
  end
end
