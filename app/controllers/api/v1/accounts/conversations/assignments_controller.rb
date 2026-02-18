class Api::V1::Accounts::Conversations::AssignmentsController < Api::V1::Accounts::Conversations::BaseController
  # assigns agent/team to a conversation
  def create
    team_resource = nil

    # Asignar equipo si se proporciona team_id
    team_resource = set_team if params.key?(:team_id)

    # Asignar agente si se proporciona assignee_id o es un AgentBot
    if params.key?(:assignee_id) || agent_bot_assignment?
      set_agent
      return # set_agent ya hace el render
    end

    # Si solo se asignó equipo, responder con el equipo
    if team_resource
      render json: team_resource
    else
      render json: nil
    end
  end

  private

  def set_agent
    resource = Conversations::AssignmentService.new(
      conversation: @conversation,
      assignee_id: params[:assignee_id],
      assignee_type: params[:assignee_type]
    ).perform

    render_agent(resource)
    resource
  end

  def render_agent(resource)
    case resource
    when User
      render partial: 'api/v1/models/agent', formats: [:json], locals: { resource: resource }
    when AgentBot
      render partial: 'api/v1/models/agent_bot_slim', formats: [:json], locals: { resource: resource }
    else
      render json: nil
    end
  end

  def set_team
    @team = Current.account.teams.find_by(id: params[:team_id])
    @conversation.update!(team: @team)
    @team
  end

  def agent_bot_assignment?
    params[:assignee_type].to_s == 'AgentBot'
  end
end
