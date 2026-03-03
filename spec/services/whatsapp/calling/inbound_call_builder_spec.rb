# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Calling::InboundCallBuilder do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp,
           account: account,
           provider: 'whatsapp_cloud',
           provider_config: {
             'phone_number_id' => '123456789',
             'business_account_id' => 'test_waba',
             'api_key' => 'test_key'
           },
           calling_enabled: true,
           calling_config: {
             'media_server_url' => 'https://media.example.com/webrtc'
           },
           sync_templates: false,
           validate_provider_config: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  let(:call_data) do
    {
      'id' => 'call-12345',
      'from' => '+1234567890',
      'to' => '+0987654321',
      'direction' => 'USER_INITIATED',
      'session' => {
        'sdp' => 'v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n...'
      }
    }
  end

  let(:metadata) do
    {
      'phone_number_id' => '123456789',
      'display_phone_number' => '+0987654321'
    }
  end

  describe '#perform' do
    context 'when calling is enabled' do
      it 'creates contact, contact_inbox, and conversation' do
        builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data,
          metadata: metadata
        )

        expect { builder.perform }.to change(Contact, :count).by(1)
                                  .and change(ContactInbox, :count).by(1)
                                  .and change(Conversation, :count).by(1)

        conversation = Conversation.last
        expect(conversation.identifier).to eq('call-12345')
        expect(conversation.contact.phone_number).to eq('+1234567890')
        expect(conversation.status).to eq('open')
      end

      it 'creates a call message in the conversation' do
        builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data,
          metadata: metadata
        )

        expect { builder.perform }.to change(Message, :count).by(1)

        message = Message.last
        expect(message.message_type).to eq('incoming')
        expect(message.content_type).to eq('voice_call')
        expect(message.content).to eq('Call initiated')
      end

      it 'uses existing contact if already exists' do
        contact = create(:contact, account: account, phone_number: '+1234567890')

        builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data,
          metadata: metadata
        )

        expect { builder.perform }.not_to change(Contact, :count)

        conversation = Conversation.last
        expect(conversation.contact).to eq(contact)
      end

      it 'uses existing conversation if call_id matches' do
        contact = create(:contact, account: account, phone_number: '+1234567890')
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
        existing_conversation = create(:conversation,
                                       account: account,
                                       inbox: inbox,
                                       contact: contact,
                                       contact_inbox: contact_inbox,
                                       identifier: 'call-12345')

        builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data,
          metadata: metadata
        )

        expect { builder.perform }.not_to change(Conversation, :count)

        returned_conversation = builder.perform
        expect(returned_conversation.id).to eq(existing_conversation.id)
      end

      it 'reuses latest conversation when lock_to_single_conversation is enabled' do
        inbox.update!(lock_to_single_conversation: true)
        contact = create(:contact, account: account, phone_number: '+1234567890')
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '+1234567890')
        old_conversation = create(:conversation,
                                  account: account,
                                  inbox: inbox,
                                  contact: contact,
                                  contact_inbox: contact_inbox,
                                  status: :resolved,
                                  updated_at: 3.days.ago)

        builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data.merge('id' => 'call-67890'),
          metadata: metadata
        )

        expect { @conversation = builder.perform }.not_to change(Conversation, :count)
        expect(@conversation.id).to eq(old_conversation.id)
      end

      it 'does not create duplicate conversation for duplicate webhook call_id' do
        first_builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data,
          metadata: metadata
        )

        second_builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data,
          metadata: metadata
        )

        expect { first_builder.perform }.to change(Conversation, :count).by(1)
        expect { second_builder.perform }.not_to change(Conversation, :count)
      end
    end

    context 'when calling is disabled' do
      let(:disabled_channel) do
        create(:channel_whatsapp,
               account: account,
               provider: 'whatsapp_cloud',
               calling_enabled: false,
               sync_templates: false,
               validate_provider_config: false)
      end
      let(:disabled_inbox) { create(:inbox, account: account, channel: disabled_channel) }

      it 'raises error' do
        builder = described_class.new(
          account: account,
          inbox: disabled_inbox,
          call_data: call_data,
          metadata: metadata
        )

        expect { builder.perform }.to raise_error(StandardError, /Calling is not enabled/)
      end
    end

    context 'with invalid data' do
      it 'handles missing contact gracefully' do
        call_data_without_from = call_data.merge('from' => nil)

        builder = described_class.new(
          account: account,
          inbox: inbox,
          call_data: call_data_without_from,
          metadata: metadata
        )

        expect { builder.perform }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe 'private methods' do
    let(:builder) do
      described_class.new(
        account: account,
        inbox: inbox,
        call_data: call_data,
        metadata: metadata
      )
    end

    describe '#ensure_contact!' do
      it 'creates new contact with phone number' do
        contact = builder.send(:ensure_contact!)

        expect(contact).to be_persisted
        expect(contact.phone_number).to eq('+1234567890')
        expect(contact.name).to eq('+1234567890')
      end

      it 'returns existing contact if found' do
        existing_contact = create(:contact, account: account, phone_number: '+1234567890')

        contact = builder.send(:ensure_contact!)

        expect(contact.id).to eq(existing_contact.id)
      end
    end

    describe '#ensure_contact_inbox!' do
      let(:contact) { create(:contact, account: account, phone_number: '+1234567890') }

      it 'creates contact_inbox if not exists' do
        contact_inbox = builder.send(:ensure_contact_inbox!, contact)

        expect(contact_inbox).to be_persisted
        expect(contact_inbox.contact).to eq(contact)
        expect(contact_inbox.inbox).to eq(inbox)
        expect(contact_inbox.source_id).to eq('+1234567890')
      end

      it 'returns existing contact_inbox if found' do
        existing_ci = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '+1234567890')

        contact_inbox = builder.send(:ensure_contact_inbox!, contact)

        expect(contact_inbox.id).to eq(existing_ci.id)
      end
    end
  end
end
