# frozen_string_literal: true

# Main orchestrator for workflow integrations
# Handles trigger detection, execution lifecycle, and message forwarding
module WorkflowIntegrations
  class Executor
    attr_reader :integration, :conversation, :event

    def initialize(integration:, conversation:, event: nil)
      @integration = integration
      @conversation = conversation
      @event = event
    end

    # Handle incoming message - decide whether to start new execution or forward to existing
    def handle_message(message)
      trigger_type = detect_trigger(message)

      if should_start_new_execution?(trigger_type)
        start_execution(message, trigger_type)
      elsif should_forward_message?
        forward_message(message)
      else
        Rails.logger.debug(
          "[Executor] No action for message message_id=#{message.id} " \
          "conversation_id=#{conversation.id} " \
          "trigger=#{trigger_type}"
        )
      end
    end

    # Handle conversation status change
    def handle_status_change
      if exiting_from_pending?
        cancel_active_execution
      elsif entering_pending?
        trigger_type = detect_trigger(nil)
        start_execution(nil, trigger_type) if should_start_new_execution?(trigger_type)
      end
    end

    private

    def detect_trigger(message)
      TriggerDetector.new(
        conversation: conversation,
        message: message,
        event: event
      ).detect_trigger_type
    end

    def should_start_new_execution?(trigger_type)
      return false if trigger_type == :existing
      return false if active_execution.present?
      return false if recently_started?

      integration.should_start_for_trigger?(trigger_type)
    end

    def should_forward_message?
      active_execution.present? && conversation.pending?
    end

    def start_execution(message, trigger_type)
      ensure_pending_status unless conversation.pending?

      payload = build_payload(message)

      integration.start_execution(
        conversation: conversation,
        trigger_type: trigger_type,
        payload: payload
      )
    rescue StandardError => e
      Rails.logger.error(
        "[Executor] Start execution failed " \
        "conversation_id=#{conversation.id} " \
        "trigger=#{trigger_type} " \
        "error=#{e.class} #{e.message}"
      )
    end

    def forward_message(message)
      payload = build_payload(message)

      integration.forward_message(execution: active_execution, payload: payload)
    rescue StandardError => e
      Rails.logger.error(
        "[Executor] Forward message failed " \
        "conversation_id=#{conversation.id} " \
        "execution_id=#{active_execution&.id} " \
        "error=#{e.class} #{e.message}"
      )
    end

    def cancel_active_execution
      return unless active_execution

      integration.cancel_execution(execution: active_execution, reason: 'Status changed from pending')

      Rails.logger.info(
        "[Executor] Cancelled active execution " \
        "execution_id=#{active_execution.id} " \
        "conversation_id=#{conversation.id}"
      )
    end

    def active_execution
      @active_execution ||= integration.active_execution_for(conversation)
    end

    def recently_started?
      return false unless active_execution
      return false unless active_execution.started_at

      active_execution.started_at > 10.seconds.ago
    end

    def exiting_from_pending?
      conversation.status_previously_changed? &&
        conversation.status_previous_change&.first == 'pending' &&
        conversation.status_previous_change&.last != 'pending'
    end

    def entering_pending?
      conversation.status_previously_changed? &&
        conversation.status_previous_change&.last == 'pending'
    end

    def ensure_pending_status
      with_bot_as_executor { conversation.pending! }
    rescue StandardError => e
      Rails.logger.warn("[Executor] Failed to set pending: #{e.message}")
    end

    def with_bot_as_executor
      previous = Current.executed_by
      Current.executed_by = integration.agent_bot
      yield
    ensure
      Current.executed_by = previous
    end

    def build_payload(message)
      PayloadBuilder.new(
        conversation: conversation,
        message: message,
        event: event
      ).build
    end
  end
end
