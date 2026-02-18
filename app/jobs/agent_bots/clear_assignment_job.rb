class AgentBots::ClearAssignmentJob < ApplicationJob
  queue_as :medium

  def perform(conversation_id, agent_bot_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation

    reset_flow_state(conversation)
    reset_assignment(conversation, agent_bot_id)
  end

  private

  def reset_flow_state(conversation)
    flow = conversation.n8n_flow
    return unless flow

    flow.update_columns(flow_id: nil, flow_webhook_url: nil, last_message_id: nil, last_triggered_at: nil)
  end

  def reset_assignment(conversation, agent_bot_id)
    return unless conversation.assignee_agent_bot_id == agent_bot_id

    updates = { assignee_agent_bot_id: nil }
    updates[:updated_at] = Time.current if conversation.has_attribute?(:updated_at)
    conversation.update_columns(updates)
  end
end
