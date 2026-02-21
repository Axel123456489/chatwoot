class Whatsapp::InteractiveMessageBuilderService
  def initialize(message:)
    @message = message
  end

  def perform
    return base_payload unless should_add_buttons?

    base_payload.merge(build_interactive_payload)
  end

  private

  def should_add_buttons?
    @message.whatsapp_buttons.present? && @message.whatsapp_buttons.is_a?(Array)
  end

  def base_payload
    {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to: @message.conversation.contact.phone_number.delete('+'),
      type: determine_message_type
    }
  end

  def determine_message_type
    should_add_buttons? ? 'interactive' : 'text'
  end

  def build_interactive_payload
    interactive_type = @message.whatsapp_interactive_type || detect_button_type

    {
      interactive: {
        type: 'button',
        body: {
          text: @message.content
        },
        action: build_action(interactive_type)
      }
    }
  end

  def detect_button_type
    # Check button types to determine if it's CTA or quick_reply
    has_url_or_phone = @message.whatsapp_buttons.any? { |btn| btn['type'].in?(%w[url phone_number]) }
    has_url_or_phone ? 'cta' : 'quick_reply'
  end

  def build_action(interactive_type)
    if interactive_type == 'cta'
      { buttons: build_cta_buttons }
    else
      { buttons: build_quick_reply_buttons }
    end
  end

  def build_cta_buttons
    @message.whatsapp_buttons.filter_map do |button|
      if button['type'].in?(%w[url phone_number])
        {
          type: 'reply',
          reply: {
            id: button['id'] || SecureRandom.uuid,
            title: button['text']
          }
        }
      else
        build_default_button(button)
      end
    end
  end

  def build_quick_reply_buttons
    @message.whatsapp_buttons.map do |button|
      {
        type: 'reply',
        reply: {
          id: button['id'] || button['text'].parameterize,
          title: button['text'].truncate(20) # WhatsApp limits button text to 20 chars
        }
      }
    end
  end

  def build_default_button(button)
    {
      type: 'reply',
      reply: {
        id: button['id'] || SecureRandom.uuid,
        title: button['text']
      }
    }
  end
end
