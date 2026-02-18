class Captain::Tools::BaseTool < RubyLLM::Tool
  prepend Captain::Tools::Instrumentation

  attr_accessor :assistant

  def initialize(assistant, user: nil)
    @assistant = assistant
    @user = user
    super()
  end

  def active?
    true
  end

  # RubyLLM::Tool already exposes metadata, but the registry expects
  # the OpenAI-style structure produced by BaseService#to_registry_format.
  # Provide a compatible shape so ToolRegistryService can register both
  # BaseService and BaseTool implementations uniformly.
  def to_registry_format
    {
      type: 'function',
      function: {
        name: tool_name,
        description: respond_to?(:description) ? description : '',
        parameters: respond_to?(:parameters) ? parameters : { type: 'object', properties: {} }
      }
    }
  end

  private

  def tool_name
    return name if respond_to?(:name)

    self.class.respond_to?(:name) ? self.class.name : self.class.to_s
  end

  def user_has_permission(permission)
    return false if @user.blank?

    account_user = AccountUser.find_by(account_id: @assistant.account_id, user_id: @user.id)
    return false if account_user.blank?

    return account_user.custom_role.permissions.include?(permission) if account_user.custom_role.present?

    account_user.administrator? || account_user.agent?
  end
end
