class Public::Api::V1::Integrations::N8nController < PublicController
  protect_from_forgery with: :null_session

  # POST /public/api/v1/integrations/n8n/automation/:id (deprecated)
  def automation
    Rails.logger.info('[N8n] automation endpoint was deprecated; returning 410')
    render json: { error: 'n8n automation endpoint removed in favor of native agent bots' }, status: :gone
  end

  # POST /public/api/v1/integrations/n8n/restart (deprecated)
  def restart
    Rails.logger.info('[N8n] restart endpoint was deprecated; returning 410')
    render json: { error: 'n8n restart endpoint removed in favor of native agent bots' }, status: :gone
  end

  # Keep switch_flow as public action so route remains accessible

  # POST /public/api/v1/integrations/n8n/switch_flow
  # Params: conversation_id, flow_id, optional flow_webhook_url
  # Same "public" protection model as other n8n endpoints (no auth, rely on obscurity + optional future token).
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
    Rails.logger.error("[N8n] switch_flow error conversation_id=#{conversation_id} error=#{e.class} #{e.message}")
    render json: { error: e.message }, status: :internal_server_error
  end
end
