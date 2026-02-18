require 'rails_helper'

RSpec.describe AgentBots::Integrations::N8nIntegration do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:default_config) do
    {
      'n8n_native' => true,
      'n8n_start_on_message' => true,
      'n8n_start_on_manual_pending' => true,
      'n8n_start_on_contact_pending' => true,
      'n8n_triggers_version' => 2
    }
  end
  let(:agent_bot) do
    create(:agent_bot,
           account: account,
           outgoing_url: 'https://n8n.example.com/webhook/start',
           bot_config: default_config)
  end
  let(:integration) { described_class.new(agent_bot) }
  let(:orchestrator) { instance_double(Integrations::N8nFlowOrchestrator) }

  before do
    allow(Integrations::N8nFlowOrchestrator).to receive(:new).with(conversation, agent_bot: agent_bot).and_return(orchestrator)
    allow(orchestrator).to receive(:start_or_update_with_full_url) do |payload:, start_url:|
      @captured_payload = payload
      @captured_start_url = start_url
      true
    end
    allow(orchestrator).to receive(:forward_message)
    allow(orchestrator).to receive(:reset_flow)
  end

  describe '#conversation_updated' do
    subject(:trigger_status_change) { integration.conversation_updated(conversation, event) }

    let(:changed_attributes) { { 'status' => %w[open pending] } }
    let(:event_data) { { changed_attributes: changed_attributes, performed_by: performer } }
    let(:event) do
      instance_double(Events::Base,
                      name: 'conversation_status_changed',
                      data: event_data)
    end

    context 'when pending is set manually by an agent' do
      let(:performer) { create(:user, account: account) }

      it 'starts the n8n flow and includes both identifiers' do
        trigger_status_change
        expect(orchestrator).to have_received(:start_or_update_with_full_url)
        expect(@captured_payload[:conversation][:id]).to eq(conversation.display_id)
        expect(@captured_payload[:conversation][:conversation_id]).to eq(conversation.id)
        expect(@captured_payload[:conversation][:display_id]).to eq(conversation.display_id)
      end

      context 'with hashed status payload' do
        let(:changed_attributes) do
          { 'status' => { previous_value: 'open', current_value: 'pending' } }
        end

        it 'parses the payload and starts the flow' do
          trigger_status_change
          expect(orchestrator).to have_received(:start_or_update_with_full_url)
          expect(@captured_payload[:conversation][:id]).to eq(conversation.display_id)
        end
      end

      context 'when manual pending trigger is disabled' do
        let(:default_config) do
          super().merge('n8n_start_on_manual_pending' => false)
        end

        it 'does not start the flow' do
          trigger_status_change
          expect(orchestrator).not_to have_received(:start_or_update_with_full_url)
        end
      end
    end

    context 'when pending is triggered by a contact message' do
      let(:performer) { conversation.contact }

      it 'starts the n8n flow when allowed' do
        trigger_status_change
        expect(orchestrator).to have_received(:start_or_update_with_full_url)
        expect(@captured_payload[:conversation][:id]).to eq(conversation.display_id)
        expect(@captured_payload[:conversation][:conversation_id]).to eq(conversation.id)
      end

      context 'with stringified change hash' do
        let(:event_data) do
          { 'changed_attributes' => { 'status' => %w[open pending] }, :performed_by => performer }
        end

        it 'still starts the flow' do
          trigger_status_change
          expect(orchestrator).to have_received(:start_or_update_with_full_url)
        end
      end

      context 'when contact pending trigger is disabled' do
        let(:default_config) do
          super().merge('n8n_start_on_contact_pending' => false)
        end

        it 'skips starting the flow' do
          trigger_status_change
          expect(orchestrator).not_to have_received(:start_or_update_with_full_url)
        end
      end
    end

    context 'when the transition is initiated by an agent bot' do
      let(:performer) { agent_bot }

      it 'skips the flow because it is bot initiated' do
        trigger_status_change
        expect(orchestrator).not_to have_received(:start_or_update_with_full_url)
      end
    end

    context 'when a flow is already active' do
      let(:performer) { create(:user, account: account) }

      before do
        conversation.create_n8n_flow!(flow_id: 'abc123', flow_webhook_url: 'https://n8n.example.com/webhook/abc123')
      end

      it 'resets and restarts the flow when coming from a non-pending status' do
        trigger_status_change
        expect(orchestrator).to have_received(:reset_flow)
        expect(orchestrator).to have_received(:start_or_update_with_full_url)
      end
    end
  end

  describe '#message_created' do
    subject(:trigger_message) { integration.message_created(message, event) }

    let(:event) { instance_double(Events::Base, name: 'message_created', data: {}) }

    context 'for the first incoming message' do
      before { conversation.update!(status: :open) }

      let(:message) do
        create(:message, conversation: conversation, account: account, inbox: inbox,
                         sender: conversation.contact, content: 'hola')
      end

      it 'starts the flow when the toggle is enabled' do
        trigger_message
        expect(orchestrator).to have_received(:start_or_update_with_full_url)
      end

      it 'moves the conversation to pending before starting' do
        expect { trigger_message }.to change { conversation.reload.status }.from('open').to('pending')
      end
    end

    context 'for a subsequent incoming message' do
      let!(:existing_message) do
        create(:message, conversation: conversation, account: account, inbox: inbox,
                         sender: conversation.contact, content: 'primer mensaje')
      end
      let(:message) do
        create(:message, conversation: conversation, account: account, inbox: inbox,
                         sender: conversation.contact, content: 'segundo mensaje')
      end

      it 'does not start a new flow' do
        trigger_message
        expect(orchestrator).not_to have_received(:start_or_update_with_full_url)
      end
    end

    context 'when a flow is already active' do
      let(:message) do
        create(:message, conversation: conversation, account: account, inbox: inbox,
                         sender: conversation.contact, content: 'hola de nuevo')
      end

      before do
        conversation.create_n8n_flow!(flow_id: 'abc123', flow_webhook_url: 'https://n8n.example.com/webhook-waiting/abc123')
      end

      context 'and the conversation remains pending' do
        it 'forwards the payload to n8n' do
          trigger_message
          expect(orchestrator).to have_received(:forward_message)
        end
      end

      context 'but the conversation is not pending' do
        before { conversation.update!(status: :open) }

        it 'does not forward the message until the status is pending again' do
          trigger_message
          expect(orchestrator).not_to have_received(:forward_message)
        end
      end
    end

    context 'when start on message was disabled before trigger v2 rollout' do
      let(:default_config) do
        super().merge('n8n_start_on_message' => false, 'n8n_triggers_version' => 1)
      end
      let(:message) do
        create(:message, conversation: conversation, account: account, inbox: inbox,
                         sender: conversation.contact, content: 'legacy toggle test')
      end

      before { conversation.update!(status: :open) }

      it 'still starts the flow for backward compatibility' do
        trigger_message
        expect(orchestrator).to have_received(:start_or_update_with_full_url)
      end
    end

    context 'when start on message is explicitly disabled in trigger v2' do
      let(:default_config) do
        super().merge('n8n_start_on_message' => false, 'n8n_triggers_version' => 2)
      end
      let(:message) do
        create(:message, conversation: conversation, account: account, inbox: inbox,
                         sender: conversation.contact, content: 'toggle off test')
      end

      before { conversation.update!(status: :open) }

      it 'skips starting the flow' do
        trigger_message
        expect(orchestrator).not_to have_received(:start_or_update_with_full_url)
      end
    end
  end
end
