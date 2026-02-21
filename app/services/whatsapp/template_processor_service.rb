class Whatsapp::TemplateProcessorService
  pattr_initialize [:channel!, :template_params, :message]

  def call
    return [nil, nil, nil, nil] if template_params.blank?

    process_template_with_params
  end

  private

  def process_template_with_params
    [
      template_params['name'],
      template_params['namespace'],
      template_params['language'],
      processed_templates_params
    ]
  end

  def find_template
    channel.message_templates.find do |t|
      t['name'] == template_params['name'] &&
        t['language']&.downcase == template_params['language']&.downcase &&
        t['status']&.downcase == 'approved'
    end
  end

  def processed_templates_params
    template = find_template
    return if template.blank?

    # Convert legacy format to enhanced format before processing
    converter = Whatsapp::TemplateParameterConverterService.new(template_params, template)
    normalized_params = converter.normalize_to_enhanced

    process_enhanced_template_params(template, normalized_params['processed_params'])
  end

  def process_enhanced_template_params(template, processed_params = nil)
    processed_params ||= template_params['processed_params']
    components = []

    components.concat(process_header_components(processed_params))
    components.concat(process_body_components(processed_params, template))
    components.concat(process_footer_components(processed_params))
    components.concat(process_button_components(processed_params))

    # Extract and save button information to message for display
    save_button_info_to_message(template, processed_params) if message.present?

    @template_params = components
  end

  def process_header_components(processed_params)
    return [] if processed_params['header'].blank?

    header_params = build_header_params(processed_params['header'])
    header_params.present? ? [{ type: 'header', parameters: header_params }] : []
  end

  def build_header_params(header_data)
    header_params = []
    header_data.each do |key, value|
      next if value.blank?

      if media_url_with_type?(key, header_data)
        media_name = header_data['media_name']
        media_param = parameter_builder.build_media_parameter(value, header_data['media_type'], media_name)
        header_params << media_param if media_param
      elsif key != 'media_type' && key != 'media_name'
        header_params << parameter_builder.build_parameter(value)
      end
    end
    header_params
  end

  def media_url_with_type?(key, header_data)
    key == 'media_url' && header_data['media_type'].present?
  end

  def process_body_components(processed_params, template)
    return [] if processed_params['body'].blank?

    body_params = processed_params['body'].filter_map do |key, value|
      next if value.blank?

      parameter_format = template['parameter_format']
      if parameter_format == 'NAMED'
        parameter_builder.build_named_parameter(key, value)
      else
        parameter_builder.build_parameter(value)
      end
    end

    body_params.present? ? [{ type: 'body', parameters: body_params }] : []
  end

  def process_footer_components(processed_params)
    return [] if processed_params['footer'].blank?

    footer_params = processed_params['footer'].filter_map do |_, value|
      next if value.blank?

      parameter_builder.build_parameter(value)
    end

    footer_params.present? ? [{ type: 'footer', parameters: footer_params }] : []
  end

  def process_button_components(processed_params)
    return [] if processed_params['buttons'].blank?

    button_params = processed_params['buttons'].filter_map.with_index do |button, index|
      next if button.blank?

      if button['type'] == 'url' || button['parameter'].present?
        {
          type: 'button',
          sub_type: button['type'] || 'url',
          index: index,
          parameters: [parameter_builder.build_button_parameter(button)]
        }
      end
    end

    button_params.compact
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end

  def save_button_info_to_message(template, processed_params)
    buttons_info = extract_buttons_from_template(template, processed_params)
    return if buttons_info.blank?

    message.whatsapp_buttons = buttons_info[:buttons]
    message.whatsapp_interactive_type = buttons_info[:type]
  end

  def extract_buttons_from_template(template, processed_params)
    button_components = template['components']&.find { |c| c['type'] == 'BUTTONS' }
    return nil if button_components.blank? || button_components['buttons'].blank?

    buttons = button_components['buttons'].map.with_index do |button, index|
      button_data = {
        type: button['type']&.downcase || 'quick_reply',
        text: button['text']
      }

      # Add URL info for URL buttons
      if button['type'] == 'URL'
        url = button['url']
        # Replace URL parameter if provided
        if processed_params['buttons'] && processed_params['buttons'][index]
          param_value = processed_params['buttons'][index]['parameter']
          url = url.gsub('{{1}}', param_value) if param_value.present?
        end
        button_data[:url] = url
      end

      # Add phone number for PHONE_NUMBER buttons
      button_data[:phone_number] = button['phone_number'] if button['type'] == 'PHONE_NUMBER'

      button_data
    end

    # Determine interactive type based on button types
    has_url = buttons.any? { |b| b[:type] == 'url' }
    interactive_type = has_url ? 'cta' : 'quick_reply'

    { buttons: buttons, type: interactive_type }
  end
end
