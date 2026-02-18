require 'rails_helper'

RSpec.describe AgentBots::ClearAssignmentJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee_agent_bot: agent_bot) }

  before do
    conversation.create_n8n_flow!(flow_id: 'flow-123', flow_webhook_url: 'https://n8n.example.com/webhook/flow-123')
  end

  it 'clears the flow state even if the bot assignment was already removed' do
    conversation.update!(assignee_agent_bot: nil)

    described_class.perform_now(conversation.id, agent_bot.id)

    flow = conversation.reload.n8n_flow
    expect(flow.flow_id).to be_nil
    expect(flow.flow_webhook_url).to be_nil
    expect(flow.last_message_id).to be_nil
  end

  it 'clears the assignee when it still belongs to the bot' do
    described_class.perform_now(conversation.id, agent_bot.id)

    expect(conversation.reload.assignee_agent_bot_id).to be_nil
  end

  it 'is a no-op when the conversation no longer exists' do
    expect { described_class.perform_now(-1, agent_bot.id) }.not_to raise_error
  end
end
