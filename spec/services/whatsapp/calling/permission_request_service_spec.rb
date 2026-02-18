# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Calling::PermissionRequestService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account) }
  let(:inbox) { create(:inbox, channel: whatsapp_channel, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+1234567890') }
  let(:user) { create(:user, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    whatsapp_channel.update(calling_config: { 'enabled' => true })
  end

  describe '#perform' do
    context 'with valid request' do
      it 'creates a permission record' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:send_message)
          .and_return({ 'messages' => [{ 'id' => 'msg_123' }] })

        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.to change(Whatsapp::CallPermission, :count).by(1)
      end

      it 'sets permission status to pending' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:send_message)
          .and_return({ 'messages' => [{ 'id' => 'msg_123' }] })

        permission = described_class.request_permission(
          account: account,
          inbox: inbox,
          contact: contact,
          user: user
        )

        expect(permission.status).to eq('pending')
        expect(permission.requested_by_user_id).to eq(user.id)
        expect(permission.requested_at).to be_present
      end

      it 'sends permission request message via WhatsApp API' do
        api_adapter = instance_double(Whatsapp::Calling::ApiAdapter)
        allow(Whatsapp::Calling::ApiAdapter).to receive(:new).and_return(api_adapter)

        expect(api_adapter).to receive(:send_message).with(
          hash_including(
            to: '+1234567890',
            type: 'text'
          )
        ).and_return({ 'messages' => [{ 'id' => 'msg_123' }] })

        described_class.request_permission(
          account: account,
          inbox: inbox,
          contact: contact,
          user: user
        )
      end

      it 'creates an activity message in conversation' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:send_message)
          .and_return({ 'messages' => [{ 'id' => 'msg_123' }] })

        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.to change(conversation.messages, :count).by(1)

        last_message = conversation.messages.last
        expect(last_message.message_type).to eq('activity')
        expect(last_message.content).to include('Solicitud de permiso')
      end
    end

    context 'with already granted permission' do
      before do
        create(:whatsapp_call_permission,
               account: account,
               inbox: inbox,
               contact: contact,
               status: 'granted')
      end

      it 'raises AlreadyRequestedError' do
        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.to raise_error(described_class::AlreadyRequestedError, /already granted/)
      end
    end

    context 'with recent pending permission' do
      before do
        create(:whatsapp_call_permission,
               account: account,
               inbox: inbox,
               contact: contact,
               status: 'pending',
               requested_at: 1.hour.ago)
      end

      it 'raises AlreadyRequestedError' do
        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.to raise_error(described_class::AlreadyRequestedError, /already pending/)
      end
    end

    context 'with old pending permission' do
      before do
        create(:whatsapp_call_permission,
               account: account,
               inbox: inbox,
               contact: contact,
               status: 'pending',
               requested_at: 25.hours.ago)
      end

      it 'allows re-requesting permission' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:send_message)
          .and_return({ 'messages' => [{ 'id' => 'msg_123' }] })

        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.not_to raise_error
      end
    end

    context 'without active conversation' do
      before do
        conversation.destroy
      end

      it 'raises PermissionError' do
        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.to raise_error(described_class::PermissionError, /No active conversation/)
      end
    end

    context 'with non-WhatsApp inbox' do
      let(:email_channel) { create(:channel_email, account: account) }
      let(:email_inbox) { create(:inbox, channel: email_channel, account: account) }

      it 'raises ArgumentError' do
        expect do
          described_class.request_permission(
            account: account,
            inbox: email_inbox,
            contact: contact,
            user: user
          )
        end.to raise_error(ArgumentError, /WhatsApp channel/)
      end
    end

    context 'with calling not enabled' do
      before do
        whatsapp_channel.update(calling_config: { 'enabled' => false })
      end

      it 'raises ArgumentError' do
        expect do
          described_class.request_permission(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user
          )
        end.to raise_error(ArgumentError, /not enabled/)
      end
    end
  end
end
