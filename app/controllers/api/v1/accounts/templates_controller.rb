class Api::V1::Accounts::TemplatesController < Api::V1::Accounts::BaseController
  before_action :set_whatsapp_inboxes

  def index
    @templates = []
    @total_count = 0

    begin
      # If no WhatsApp inboxes are found, return demo data
      if @whatsapp_inboxes.empty?
        @templates = demo_templates
        @total_count = @templates.size
        return
      end

      # Filter inboxes based on inbox_id parameter if provided
      target_inboxes = if permitted_params[:inbox_id].present?
                         @whatsapp_inboxes.select { |inbox| inbox.id == permitted_params[:inbox_id].to_i }
                       else
                         @whatsapp_inboxes
                       end

      target_inboxes.each do |inbox|
        next if inbox&.channel&.message_templates.blank?

        templates = filter_templates(inbox.channel.message_templates, inbox)
        @templates.concat(templates) if templates.any?
      end

      # If no templates found, return demo data
      @templates = demo_templates if @templates.empty?

      # Apply sorting and pagination
      @templates = apply_filters_and_sort(@templates)
      @total_count = @templates.size
      @templates = paginate_templates(@templates)
    rescue StandardError => e
      Rails.logger.error "Error in templates index: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @templates = demo_templates
      @total_count = @templates.size
    end
  end

  def show
    inbox = @whatsapp_inboxes.find { |i| i.id == params[:inbox_id].to_i }
    return render json: { error: 'Inbox not found' }, status: :not_found unless inbox

    @template = find_template_in_inbox(inbox, params[:id])
    return render json: { error: 'Template not found' }, status: :not_found unless @template
  end

  def inboxes
    render json: {
      payload: @whatsapp_inboxes.map do |inbox|
        {
          id: inbox.id,
          name: inbox.name,
          channel_type: inbox.channel_type,
          phone_number: inbox.channel.phone_number,
          provider: inbox.channel.provider,
          templates_count: inbox.channel.message_templates&.size || 0,
          last_sync: inbox.channel.message_templates_last_updated
        }
      end
    }
  end

  def create_template
    inbox_id = params[:inbox_id] || params.dig(:template, :inbox_id)
    inbox = @whatsapp_inboxes.find(inbox_id)

    # Build components from parameters
    components = build_template_components(template_params)

    response = inbox.channel.provider_service.create_message_template(
      name: template_params[:name],
      language: template_params[:language] || 'en',
      category: template_params[:category]&.upcase || 'UTILITY',
      components: components
    )

    if response && (response['id'] || response['success'])
      render json: {
        message: 'Template submitted for approval. It will be available after Meta approval (24-48 hours)',
        template_id: response['id'],
        data: response
      }
    else
      error_message = response&.dig('error', 'message') || response&.dig('error') || 'Failed to create template'
      render json: { error: error_message }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Error creating template: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_whatsapp_inboxes
    @whatsapp_inboxes = Current.account.inboxes
                               .includes(:channel)
                               .where(channel_type: 'Channel::Whatsapp')
  rescue StandardError => e
    Rails.logger.error "Error fetching WhatsApp inboxes: #{e.message}"
    @whatsapp_inboxes = []
  end

  def filter_templates(templates, inbox)
    return [] unless templates.is_a?(Array)

    templates.filter_map do |template|
      next unless template.is_a?(Hash)

      # Convert WhatsApp template format to our unified format
      {
        id: template['id'] || template[:id],
        name: template['name'] || template[:name] || 'Unnamed Template',
        category: (template['category'] || template[:category])&.downcase || 'utility',
        channel_type: 'whatsapp',
        content: extract_template_content(template),
        content_type: determine_content_type(template),
        language: template['language'] || template[:language] || 'en',
        status: (template['status'] || template[:status])&.downcase || 'approved',
        components: template['components'] || template[:components] || [],
        meta: template.except('id', 'name', 'category', 'language', 'status', 'components') || {},
        inbox_id: inbox.id,
        inbox_name: inbox.name,
        created_at: inbox.created_at,
        updated_at: inbox.channel.message_templates_last_updated || inbox.updated_at
      }
    end.select do |template|
      # Apply filters
      (permitted_params[:category].blank? || template[:category] == permitted_params[:category]) &&
        (permitted_params[:language].blank? || template[:language] == permitted_params[:language]) &&
        (permitted_params[:status].blank? || template[:status] == permitted_params[:status])
    end
  rescue StandardError => e
    Rails.logger.error "Error filtering templates: #{e.message}"
    []
  end

  def extract_template_content(template)
    return 'No content' unless template.is_a?(Hash)

    components = template['components'] || template[:components] || []
    body_component = components.find { |c| c.is_a?(Hash) && c['type'] == 'BODY' }

    content = body_component&.dig('text') ||
              template['name'] ||
              template[:name] ||
              'No content'

    content.to_s
  rescue StandardError
    'No content'
  end

  def determine_content_type(template)
    return 'text' unless template.is_a?(Hash)

    components = template['components'] || template[:components] || []
    return 'text' unless components.is_a?(Array)

    has_media = components.any? { |c| c.is_a?(Hash) && c['type'] == 'HEADER' && c['format'] != 'TEXT' }
    has_buttons = components.any? { |c| c.is_a?(Hash) && c['type'] == 'BUTTONS' }

    return 'media' if has_media
    return 'quick_reply' if has_buttons

    'text'
  rescue StandardError
    'text'
  end

  def apply_filters_and_sort(templates)
    return [] unless templates.is_a?(Array)

    # Sort by name by default
    templates.sort_by { |t| t[:name] || '' }
  rescue StandardError
    []
  end

  def paginate_templates(templates)
    return [] unless templates.is_a?(Array)

    page = (permitted_params[:page] || 1).to_i
    page = 1 if page < 1

    per_page = 10
    start_index = (page - 1) * per_page

    templates[start_index, per_page] || []
  rescue StandardError
    []
  end

  def find_template_in_inbox(inbox, template_id)
    inbox.channel.message_templates&.find { |t| t['id'] == template_id }
  end

  def template_params
    params.require(:template).permit(
      :name,
      :language,
      :category,
      :inbox_id,
      :header_type,
      :header_text,
      :body_text,
      :footer_text,
      :button_type,
      buttons: [:type, :text],
      variables: []
    )
  end

  def build_template_components(params)
    components = []

    placeholder_regex = /\{\{\s*(\d+)\s*\}\}/
    extract_indices = lambda do |text|
      return [] unless text.is_a?(String)

      text.scan(placeholder_regex).flatten.map(&:to_i).uniq.sort
    end

    # Header component
    if params[:header_text].present? || params[:header_type].present?
      header = {
        type: 'HEADER',
        format: params[:header_type]&.upcase || 'TEXT'
      }

      if params[:header_type] == 'text' && params[:header_text].present?
        header[:text] = params[:header_text]
        # Include header examples if it contains variables like {{1}}
        header_indices = extract_indices.call(params[:header_text])
        if header_indices.any?
          header_examples = header_indices.map { |i| "Example #{i}" }
          header[:example] = { header_text: header_examples }
        end
      end

      components << header
    end

    # Body component (required)
    if params[:body_text].present?
      body_component = {
        type: 'BODY',
        text: params[:body_text]
      }
      # Build example for body variables if placeholders exist
      body_indices = extract_indices.call(params[:body_text])
      if body_indices.any?
        provided_vars = Array(params[:variables]).map(&:to_s)
        # Map by index order; fall back to default placeholders when not provided
        body_examples = body_indices.each_with_index.map do |idx, i|
          provided_vars[i].presence || "example_#{idx}"
        end
        body_component[:example] = { body_text: [body_examples] }
      end
      components << body_component
    end

    # Footer component
    if params[:footer_text].present?
      components << {
        type: 'FOOTER',
        text: params[:footer_text]
      }
    end

    # Buttons component
    if params[:buttons].present? && params[:buttons].any?
      buttons_array = params[:buttons].map do |button|
        {
          type: button[:type] || 'QUICK_REPLY',
          text: button[:text]
        }
      end

      components << {
        type: 'BUTTONS',
        buttons: buttons_array
      }
    end

    components
  end

  def permitted_params
    params.permit(:category, :channel_type, :status, :language, :page, :inbox_id)
  end

  def demo_templates
    [
      {
        id: '1',
        name: 'Welcome Message',
        category: 'marketing',
        channel_type: 'whatsapp',
        content: 'Welcome to our service! How can we help you today?',
        content_type: 'text',
        language: 'en',
        status: 'approved',
        components: [
          {
            type: 'BODY',
            text: 'Welcome to our service! How can we help you today?'
          }
        ],
        meta: {},
        inbox_id: 0,
        inbox_name: 'Demo WhatsApp',
        created_at: Time.current,
        updated_at: Time.current
      },
      {
        id: '2',
        name: 'Order Confirmation',
        category: 'utility',
        channel_type: 'whatsapp',
        content: 'Your order {{1}} has been confirmed. Expected delivery: {{2}}',
        content_type: 'text',
        language: 'en',
        status: 'approved',
        components: [
          {
            type: 'BODY',
            text: 'Your order {{1}} has been confirmed. Expected delivery: {{2}}'
          }
        ],
        meta: {},
        inbox_id: 0,
        inbox_name: 'Demo WhatsApp',
        created_at: Time.current,
        updated_at: Time.current
      },
      {
        id: '3',
        name: 'Support Hours',
        category: 'utility',
        channel_type: 'whatsapp',
        content: 'Our support team is available Monday to Friday, 9 AM to 6 PM.',
        content_type: 'text',
        language: 'en',
        status: 'approved',
        components: [
          {
            type: 'BODY',
            text: 'Our support team is available Monday to Friday, 9 AM to 6 PM.'
          }
        ],
        meta: {},
        inbox_id: 0,
        inbox_name: 'Demo WhatsApp',
        created_at: Time.current,
        updated_at: Time.current
      }
    ]
  end
end
