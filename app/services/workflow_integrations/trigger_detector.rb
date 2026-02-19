# frozen_string_literal: true

# Detects the trigger type for workflow executions based on conversation state and events
module WorkflowIntegrations
  class TriggerDetector
    attr_reader :conversation, :message, :event

    def initialize(conversation:, message: nil, event: nil)
      @conversation = conversation
      @message = message
      @event = event
    end

    def detect_trigger_type
      return :reopen if message_reopened_conversation?
      return :new_conversation if new_conversation?
      return :manual_pending if manual_pending_change?
      return :contact_pending if contact_pending_change?
      return :webwidget if webwidget_trigger?
      return :manual if manual_trigger?

      :existing
    end

    private

    def message_reopened_conversation?
      return false unless event&.data

      event.data[:reopened_conversation] == true || event.data['reopened_conversation'] == true
    end

    def new_conversation?
      return false unless message
      return false unless message.incoming?

      # Es nueva conversación solo si NO hay mensajes previos (ni incoming ni outgoing)
      # Si un agente ya escribió antes, no es una conversación nueva
      !conversation.messages.where('id < ?', message.id).exists?
    end

    def manual_pending_change?
      return false unless status_changed_to_pending?

      actor = event&.data&.dig(:performed_by) || event&.data&.dig('performed_by')
      actor.is_a?(User)
    end

    def contact_pending_change?
      return false unless status_changed_to_pending?

      actor = event&.data&.dig(:performed_by) || event&.data&.dig('performed_by')
      actor.is_a?(Contact)
    end

    def webwidget_trigger?
      return false unless event

      event_name = event.try(:name) || event.try(:event) || event.try(:type)
      event_name.to_s.include?('webwidget')
    end

    def manual_trigger?
      # Check if this is a manual API call (no message, no status change)
      message.nil? && !status_changed_to_pending?
    end

    def status_changed_to_pending?
      return false unless event&.data

      changed = event.data[:changed_attributes] || event.data['changed_attributes']
      return false unless changed

      status_change = changed['status'] || changed[:status]
      return false unless status_change

      extract_current_status(status_change) == 'pending'
    end

    def extract_current_status(status_change)
      case status_change
      when Array
        status_change.last
      when Hash
        status_change[:current_value] || status_change['current_value']
      else
        status_change
      end.to_s
    end
  end
end
