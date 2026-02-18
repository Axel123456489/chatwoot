class Api::V1::Accounts::Inboxes::MessageTemplatesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :validate_whatsapp_channel

  def update
    template = find_template_by_id(params[:id])
    return render json: { error: 'Template not found' }, status: :not_found unless template

    # Bloquear cambios en nombre/idioma/categoría desde el cliente
    if (update_params[:name].present? && update_params[:name] != template['name']) ||
       (update_params[:language].present? && update_params[:language].to_s != template['language'].to_s) ||
       (update_params[:category].present? && update_params[:category].to_s.upcase != template['category'].to_s.upcase)
      return render json: { error: 'No puedes cambiar el nombre, el idioma o la categoría de una plantilla aprobada. Crea una nueva plantilla para esos cambios.' },
                    status: :unprocessable_entity
    end

    begin
      # Build components from params similar to create
      components = build_template_components(update_params)

      # Siempre usar los valores originales para evitar crear una variante nueva
      name_for_update = template['name']
      # IMPORTANTE: no normalizar en updates; usar exactamente el valor original para evitar cambios de variante (p. ej., es -> es_ES)
      language_for_update = template['language'].presence || 'en'
      category_for_update = template['category'].presence || 'UTILITY'

      # No hay un endpoint de edición; re‑enviar con mismo name/language/category para revisión
      response = @inbox.channel.provider_service.create_message_template(
        name: name_for_update,
        language: language_for_update,
        category: category_for_update,
        components: components
      )

      if response && (response['id'] || response['success'])
        Channels::Whatsapp::TemplatesSyncJob.perform_later(@inbox.channel)
        render json: {
          message: 'Template updated and resubmitted for approval',
          template_id: response['id'],
          data: response,
          used_language: language_for_update,
          used_category: category_for_update
        }, status: :ok
      else
        error_message = response&.dig('error', 'message') || response&.dig('error') || 'Failed to update template'
        error_details = response&.dig('error', 'error_data') || response
        render json: { error: error_message, details: error_details }, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error "Error updating template: #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def destroy
    template = find_template_by_id(params[:id])
    return render json: { error: 'Template not found' }, status: :not_found unless template

    begin
      # Call WhatsApp API to delete the template
      response = @inbox.channel.provider_service.delete_message_template(
        name: template['name'],
        language: template['language']
      )

      if response && !response['error']
        # Remove template from local storage by syncing templates
        sync_templates_after_deletion
        render json: { message: 'Template deleted successfully' }, status: :ok
      else
        error_message = response&.dig('error', 'message') || 'Failed to delete template'
        render json: { error: error_message }, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error "Error deleting template: #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Inbox not found' }, status: :not_found
  end

  def validate_whatsapp_channel
    return if @inbox.channel_type == 'Channel::Whatsapp'

    render json: { error: 'Template operations are only available for WhatsApp channels' }, status: :unprocessable_entity
  end

  def find_template_by_id(template_id)
    return nil unless @inbox.channel.message_templates.is_a?(Array)

    @inbox.channel.message_templates.find { |template| template['id'] == template_id }
  end

  def sync_templates_after_deletion
    # Trigger template sync to refresh the local cache
    Channels::Whatsapp::TemplatesSyncJob.perform_later(@inbox.channel)
  end

  def update_params
    params.require(:template).permit(
      :name,
      :language,
      :category,
      :header_type,
      :header_text,
      :body_text,
      :footer_text,
      buttons: [:type, :text],
      variables: []
    )
  end

  # Normalize two-letter language codes to locale codes expected by WhatsApp template API
  def normalize_language(lang)
    return 'en_US' if lang.blank?

    code = lang.to_s
    return code if code.match?(/^[a-z]{2}_[A-Z]{2}$/)

    mappings = {
      'en' => 'en_US',
      'es' => 'es_ES',
      'pt' => 'pt_BR',
      'fr' => 'fr_FR',
      'de' => 'de_DE',
      'it' => 'it_IT',
      'nl' => 'nl_NL',
      'tr' => 'tr_TR',
      'ar' => 'ar_AR',
      'hi' => 'hi_IN',
      'id' => 'id_ID',
      'ja' => 'ja_JP',
      'ko' => 'ko_KR',
      'pl' => 'pl_PL',
      'ru' => 'ru_RU',
      'vi' => 'vi_VN',
      'th' => 'th_TH',
      'zh' => 'zh_CN'
    }

    mappings[code] || code
  end

  def normalize_category(cat)
    up = cat.to_s.upcase
    return up if %w[UTILITY MARKETING AUTHENTICATION].include?(up)

    'UTILITY'
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

    # Body component (required if provided)
    if params[:body_text].present?
      body_component = {
        type: 'BODY',
        text: params[:body_text]
      }
      # Build example for body variables if placeholders exist
      body_indices = extract_indices.call(params[:body_text])
      if body_indices.any?
        provided_vars = Array(params[:variables]).map(&:to_s)
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
end
