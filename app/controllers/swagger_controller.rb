class SwaggerController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def respond
    unless swagger_enabled?
      Rails.logger.warn("[SwaggerController] Swagger disabled. ENABLE_SWAGGER=#{ENV.fetch('ENABLE_SWAGGER', 'not set')}")
      head :not_found
      return
    end

    file_path = Rails.root.join('swagger', derived_path)

    unless File.exist?(file_path)
      Rails.logger.warn("[SwaggerController] File not found: #{file_path}")
      head :not_found
      return
    end

    content = File.read(file_path)
    content_type = derive_content_type(derived_path)

    render plain: content, content_type: content_type
  end

  private

  def swagger_enabled?
    return true if Rails.env.development? || Rails.env.test?

    enable_swagger = ENV.fetch('ENABLE_SWAGGER', 'false')
    ActiveModel::Type::Boolean.new.cast(enable_swagger)
  end

  def derived_path
    params[:path] ||= 'index.html'
    path = Rack::Utils.clean_path_info(params[:path])
    path << ".#{Rack::Utils.clean_path_info(params[:format])}" unless path.ends_with?(params[:format].to_s)
    path
  end

  def derive_content_type(path)
    case File.extname(path).downcase
    when '.html'
      'text/html; charset=utf-8'
    when '.json'
      'application/json; charset=utf-8'
    when '.yml', '.yaml'
      'application/x-yaml; charset=utf-8'
    else
      'text/plain; charset=utf-8'
    end
  end
end
