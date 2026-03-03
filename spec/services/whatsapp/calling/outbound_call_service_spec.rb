# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Calling::OutboundCallService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud') }
  let(:inbox) { create(:inbox, channel: whatsapp_channel, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+1234567890') }
  let(:user) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:permission) do
    create(:whatsapp_call_permission,
           account: account,
           inbox: inbox,
           contact: contact,
           status: 'granted',
           remaining_calls: 5)
  end

  before do
    # Enable calling in channel
    whatsapp_channel.update(calling_config: { 'enabled' => true })
    permission
  end

  describe '#perform' do
    context 'with valid permission' do
      it 'initiates a call successfully' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:initiate_call)
          .and_return({ 'calls' => [{ 'id' => 'test_call_123' }] })

        result = described_class.initiate_call(
          account: account,
          inbox: inbox,
          contact: contact,
          user: user,
          conversation: conversation
        )

        expect(result[:call_id]).to eq('test_call_123')
        expect(result[:status]).to eq('initiated')
        expect(permission.reload.remaining_calls).to eq(4)
      end

      it 'creates a call message in conversation' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:initiate_call)
          .and_return({ 'calls' => [{ 'id' => 'test_call_123' }] })

        expect do
          described_class.initiate_call(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user,
            conversation: conversation
          )
        end.to change(conversation.messages, :count).by(1)

        last_message = conversation.messages.last
        expect(last_message.content_type).to eq('voice_call')
        expect(last_message.content_attributes['call_id']).to eq('test_call_123')
      end

      it 'stores call data in conversation' do
        allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:initiate_call)
          .and_return({ 'calls' => [{ 'id' => 'test_call_123' }] })

        described_class.initiate_call(
          account: account,
          inbox: inbox,
          contact: contact,
          user: user,
          conversation: conversation
        )

        conversation.reload
        call_data = conversation.additional_attributes['whatsapp_call']

        expect(call_data['id']).to eq('test_call_123')
        expect(call_data['direction']).to eq('outbound')
        expect(call_data['status']).to eq('initiated')
      end

      context 'when no conversation is passed' do
        before do
          allow_any_instance_of(Whatsapp::Calling::ApiAdapter).to receive(:initiate_call)
            .and_return({ 'calls' => [{ 'id' => 'test_call_123' }] })
        end

        it 'reuses old conversation when lock_to_single_conversation is enabled' do
          inbox.update!(lock_to_single_conversation: true)
          old_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 3.days.ago)

          expect do
            @result = described_class.initiate_call(
              account: account,
              inbox: inbox,
              contact: contact,
              user: user
            )
          end.not_to change(Conversation, :count)

          expect(@result[:conversation].id).to eq(old_conversation.id)
        end

        it 'creates a new conversation for old threads when lock_to_single_conversation is disabled' do
          inbox.update!(lock_to_single_conversation: false)
          create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 3.days.ago)

          expect do
            described_class.initiate_call(
              account: account,
              inbox: inbox,
              contact: contact,
              user: user
            )
          end.to change(Conversation, :count).by(1)
        end
      end
    end

    context 'without permission' do
      before do
        permission.destroy
      end

      it 'raises PermissionError' do
        expect do
          described_class.initiate_call(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user,
            conversation: conversation
          )
        end.to raise_error(described_class::PermissionError, /No call permission/)
      end
    end

    context 'with expired permission' do
      before do
        permission.update(expires_at: 1.day.ago)
      end

      it 'raises PermissionError' do
        expect do
          described_class.initiate_call(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user,
            conversation: conversation
          )
        end.to raise_error(described_class::PermissionError, /expired/)
      end
    end

    context 'with no remaining calls' do
      before do
        permission.update(remaining_calls: 0)
      end

      it 'raises LimitError' do
        expect do
          described_class.initiate_call(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user,
            conversation: conversation
          )
        end.to raise_error(described_class::LimitError, /Daily call limit/)
      end
    end

    context 'with calling not enabled' do
      before do
        whatsapp_channel.update(calling_config: { 'enabled' => false })
      end

      it 'raises CallInitiationError' do
        expect do
          described_class.initiate_call(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user,
            conversation: conversation
          )
        end.to raise_error(described_class::CallInitiationError, /not enabled/)
      end
    end

    context 'with active call in progress' do
      before do
        conversation.update(
          additional_attributes: {
            'whatsapp_call' => {
              'id' => 'existing_call',
              'status' => 'connected'
            }
          }
        )
      end

      it 'raises CallInitiationError' do
        expect do
          described_class.initiate_call(
            account: account,
            inbox: inbox,
            contact: contact,
            user: user,
            conversation: conversation
          )
        end.to raise_error(described_class::CallInitiationError, /already an active call/)
      end
    end
  end
end
