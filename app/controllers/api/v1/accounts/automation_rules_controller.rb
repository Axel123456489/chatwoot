class Api::V1::Accounts::AutomationRulesController < Api::V1::Accounts::BaseController
  include AttachmentConcern

  before_action :check_authorization
  before_action :fetch_automation_rule, only: [:show, :update, :destroy, :clone]

  def index
    @automation_rules = Current.account.automation_rules
  end

  def show; end

  def create
    blobs, actions, error = validate_and_prepare_attachments(params[:actions])
    return render_could_not_create_error(error) if error

    @automation_rule = Current.account.automation_rules.new(automation_rules_permit)
    @automation_rule.actions = actions
    @automation_rule.conditions = params[:conditions]
    # Backend debug logs for incoming automation payloads
    Rails.logger.info("[Automation][API] create params actions=#{params[:actions].inspect} conditions=#{params[:conditions].inspect}")

    return render_could_not_create_error(@automation_rule.errors.messages) unless @automation_rule.valid?

    @automation_rule.save!
    Rails.logger.info("[Automation][API] created rule id=#{@automation_rule.id} actions=#{@automation_rule.actions.inspect} conditions=#{@automation_rule.conditions.inspect}")
    blobs.each { |blob| @automation_rule.files.attach(blob) }
    process_attachments
    @automation_rule
  rescue StandardError => e
    Rails.logger.error("[Automation][API] create failed: #{e.class} #{e.message}")
    Rails.logger.warn("[Automation][API] create validation errors: #{@automation_rule&.errors&.full_messages}")
    raise e
  end

  def update
    blobs, actions, error = validate_and_prepare_attachments(params[:actions], @automation_rule)
    return render_could_not_create_error(error) if error

    ActiveRecord::Base.transaction do
      # Backend debug logs for incoming automation payloads
      Rails.logger.info("[Automation][API] update rule id=#{params[:id]} incoming actions=#{params[:actions].inspect} conditions=#{params[:conditions].inspect}")

      @automation_rule.assign_attributes(automation_rules_permit)
      @automation_rule.actions = actions if params[:actions]
      @automation_rule.conditions = params[:conditions] if params[:conditions]
      @automation_rule.save!
      Rails.logger.info("[Automation][API] updated rule id=#{@automation_rule.id} actions=#{@automation_rule.actions.inspect} conditions=#{@automation_rule.conditions.inspect}")
      blobs.each { |blob| @automation_rule.files.attach(blob) }
      process_attachments
    rescue StandardError => e
      Rails.logger.error("[Automation][API] update failed for rule id=#{@automation_rule&.id}: #{e.class} #{e.message}")
      Rails.logger.warn("[Automation][API] update validation errors: #{@automation_rule&.errors&.full_messages}")
      render_could_not_create_error(@automation_rule.errors.messages)
    end
  end

  def destroy
    @automation_rule.destroy!
    head :ok
  end

  def clone
    automation_rule = Current.account.automation_rules.find_by(id: params[:automation_rule_id])
    new_rule = automation_rule.dup
    new_rule.save!
    @automation_rule = new_rule
  end

  private

  def automation_rules_permit
    params.permit(
      :name, :description, :event_name, :active,
      conditions: [:attribute_key, :filter_operator, :query_operator, :custom_attribute_type, { values: [] }],
      actions: [:action_name, { action_params: [] }]
    )
  end

  def fetch_automation_rule
    @automation_rule = Current.account.automation_rules.find_by(id: params[:id])
  end

  # Safe no-op to avoid errors during logging verification; extend if attachments are used
  def process_attachments
    # no-op
  end
end
