class Api::V1::Integrations::N8nController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/v1/integrations/n8n/switch_flow
  # Params: conversation_id, flow_id, optional flow_webhook_url
  def switch_flow
    conversation_id = params[:conversation_id]
    new_flow_id = params[:flow_id]
    new_start_url = params[:flow_webhook_url]

    return render json: { error: 'conversation_id missing' }, status: :bad_request if conversation_id.blank?
    return render json: { error: 'flow_id missing' }, status: :bad_request if new_flow_id.blank?

    conversation = Conversation.find_by(id: conversation_id)
    return render json: { error: 'conversation not found' }, status: :not_found unless conversation

    flow = N8nFlow.find_or_create_by!(conversation_id: conversation.id)
    attrs = { flow_id: new_flow_id, last_triggered_at: Time.current }
    attrs[:flow_webhook_url] = new_start_url if new_start_url.present?
    flow.update!(attrs)

    render json: { message: 'Flow switched', conversation_id: conversation.id, flow_id: flow.flow_id }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[N8n][API V1] switch_flow error conversation_id=#{conversation_id} error=#{e.class} #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end
end
