# frozen_string_literal: true

# == Schema Information
#
# Table name: workflow_integrations
#
#  id           :bigint           not null, primary key
#  config       :jsonb            not null
#  enabled      :boolean          default(TRUE), not null
#  metadata     :jsonb            not null
#  status       :string           default("active"), not null
#  type         :string           not null
#  version      :string           default("1.0")
#  webhook_url  :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  agent_bot_id :bigint           not null
#
# Indexes
#
#  index_workflow_integrations_on_agent_bot_id  (agent_bot_id)
#  index_workflow_integrations_on_enabled       (enabled)
#  index_workflow_integrations_on_status        (status)
#  index_workflow_integrations_on_type          (type)
#  index_workflow_integrations_unique_bot_type  (agent_bot_id,type) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_bot_id => agent_bots.id)
#

module WorkflowIntegrations
  class N8n < WorkflowIntegration
    # Config accessors for n8n-specific settings
    store_accessor :config,
                   :start_on_new_conversation,
                   :start_on_reopen,
                   :start_on_manual_pending,
                   :start_on_contact_pending,
                   :triggers_version

    validates :start_on_new_conversation, inclusion: { in: [true, false] }, allow_nil: true
    validates :start_on_reopen, inclusion: { in: [true, false] }, allow_nil: true
    validates :start_on_manual_pending, inclusion: { in: [true, false] }, allow_nil: true
    validates :start_on_contact_pending, inclusion: { in: [true, false] }, allow_nil: true
    validates :triggers_version, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    after_initialize :set_default_config, if: :new_record?

    # Main entry points (called by Executor)
    def start_execution(conversation:, trigger_type:, payload:)
      unless can_start_execution?(conversation)
        Rails.logger.info("[N8n] Cannot start execution conversation_id=#{conversation.id} reason=already_active")
        return nil
      end

      unless should_start_for_trigger?(trigger_type)
        Rails.logger.info("[N8n] Skipping start conversation_id=#{conversation.id} trigger_type=#{trigger_type} reason=disabled")
        return nil
      end

      conversation.with_lock do
        execution = workflow_executions.create!(
          conversation: conversation,
          trigger_type: trigger_type,
          webhook_url: webhook_url,
          status: 'pending',
          metadata: {
            payload_keys: payload.keys,
            trigger_context: trigger_type
          }
        )

        begin
          response = post_to_webhook(webhook_url, payload)
          flow_id = extract_flow_id(response)

          execution.start!(execution_id: flow_id, webhook_url: webhook_url)
          assign_bot_to_conversation(conversation)

          Rails.logger.info(
            "[N8n] Started execution_id=#{execution.id} " \
            "flow_id=#{flow_id} " \
            "conversation_id=#{conversation.id} " \
            "trigger=#{trigger_type}"
          )

          execution
        rescue StandardError => e
          execution.fail!(error_message: "Failed to start: #{e.message}")
          Rails.logger.error("[N8n] Start failed: #{e.class} #{e.message}")
          raise
        end
      end
    end

    def forward_message(execution:, payload:)
      unless execution.active?
        Rails.logger.warn("[N8n] Cannot forward to inactive execution_id=#{execution.id} status=#{execution.status}")
        return
      end

      waiting_url = build_waiting_url(execution)
      unless waiting_url
        Rails.logger.error("[N8n] Cannot build waiting URL execution_id=#{execution.id}")
        return
      end

      begin
        post_to_webhook(waiting_url, payload)
        execution.mark_activity!(message_id: payload.dig(:message, :id))

        Rails.logger.info(
          "[N8n] Forwarded message execution_id=#{execution.id} " \
          "conversation_id=#{execution.conversation_id}"
        )
      rescue StandardError => e
        Rails.logger.error(
          "[N8n] Forward failed execution_id=#{execution.id} " \
          "error=#{e.class} #{e.message}"
        )
        # Don't mark as failed - the flow might still be running
      end
    end

    def cancel_execution(execution:, reason: nil)
      execution.cancel!(reason: reason)
      clear_bot_assignment(execution.conversation)

      Rails.logger.info(
        "[N8n] Cancelled execution_id=#{execution.id} " \
        "conversation_id=#{execution.conversation_id} " \
        "reason=#{reason}"
      )
    end

    # Trigger decision logic
    def should_start_for_trigger?(trigger_type)
      case trigger_type.to_sym
      when :new_conversation
        boolean_config_value(:start_on_new_conversation, default: true)
      when :reopen
        boolean_config_value(:start_on_reopen, default: true)
      when :manual_pending
        boolean_config_value(:start_on_manual_pending, default: true)
      when :contact_pending
        boolean_config_value(:start_on_contact_pending, default: false)
      when :manual
        true # Manual triggers always allowed
      when :webwidget
        true # Webwidget triggers always allowed
      else
        false
      end
    end

    private

    def set_default_config
      self.config ||= {}
      self.start_on_new_conversation = true if start_on_new_conversation.nil?
      self.start_on_reopen = true if start_on_reopen.nil?
      self.start_on_manual_pending = true if start_on_manual_pending.nil?
      self.start_on_contact_pending = false if start_on_contact_pending.nil?
      self.triggers_version = 2 if triggers_version.nil?
    end

    def boolean_config_value(key, default: nil)
      value = config_value(key, default: default)
      ActiveRecord::Type::Boolean.new.cast(value)
    end

    def build_waiting_url(execution)
      return nil if execution.webhook_url.blank? || execution.execution_id.blank?

      uri = URI.parse(execution.webhook_url)
      path = uri.path || ''

      # Extract base path (before /webhook/)
      prefix = if path.include?('/webhook/')
                 path.split('/webhook/').first
               else
                 path.gsub(%r{/+$}, '')
               end

      port_part = standard_port?(uri) ? '' : ":#{uri.port}"
      base = "#{uri.scheme}://#{uri.host}#{port_part}#{prefix}".gsub(%r{/+$}, '')

      "#{base}/webhook-waiting/#{execution.execution_id}"
    rescue URI::InvalidURIError => e
      Rails.logger.error("[N8n] Invalid webhook URL: #{e.message}")
      nil
    end

    def standard_port?(uri)
      (uri.scheme == 'https' && uri.port == 443) || (uri.scheme == 'http' && uri.port == 80)
    end

    def build_cancel_url(execution)
      return nil if execution.webhook_url.blank? || execution.execution_id.blank?

      uri = URI.parse(execution.webhook_url)
      path = uri.path || ''

      # Extract base path (before /webhook/)
      prefix = if path.include?('/webhook/')
                 path.split('/webhook/').first
               else
                 path.gsub(%r{/+$}, '')
               end

      port_part = standard_port?(uri) ? '' : ":#{uri.port}"
      base = "#{uri.scheme}://#{uri.host}#{port_part}#{prefix}".gsub(%r{/+$}, '')

      "#{base}/webhook-cancel/#{execution.execution_id}"
    rescue URI::InvalidURIError => e
      Rails.logger.error("[N8n] Invalid webhook URL: #{e.message}")
      nil
    end

    def extract_flow_id(response)
      body = response.respond_to?(:parsed_response) ? response.parsed_response : {}
      flow_id = body.is_a?(Hash) ? body['id'] : nil
      flow_id.presence || "execution-#{Time.now.to_i}"
    end

    def post_to_webhook(url, payload)
      WorkflowIntegrations::WebhookPoster.new(url, payload).execute
    end

    def assign_bot_to_conversation(conversation)
      return if agent_bot.blank?
      return if conversation.assignee_agent_bot_id == agent_bot.id
      return if conversation.assignee_id.present?

      conversation.update!(assignee_agent_bot: agent_bot, assignee: nil)
    end

    def clear_bot_assignment(conversation)
      return if agent_bot.blank?
      return unless conversation.assignee_agent_bot_id == agent_bot.id

      AgentBots::ClearAssignmentJob.perform_later(conversation.id, agent_bot.id)
    end
  end
end
