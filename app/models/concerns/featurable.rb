module Featurable
  extend ActiveSupport::Concern

  MAX_BIGINT_FEATURE_FLAGS = 63
  OVERFLOW_FEATURE_ATTRIBUTE = 'overflow_feature_flags'.freeze

  QUERY_MODE = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze

  FEATURE_LIST = YAML.safe_load(Rails.root.join('config/features.yml').read).freeze

  OVERFLOW_FEATURE_NAMES = FEATURE_LIST.each_with_index.filter_map do |feature, index|
    feature['name'] if index >= MAX_BIGINT_FEATURE_FLAGS
  end.freeze

  STANDARD_FEATURE_NAMES = FEATURE_LIST.each_with_index.filter_map do |feature, index|
    feature['name'] if index < MAX_BIGINT_FEATURE_FLAGS
  end.freeze

  STANDARD_FEATURE_POSITIONS = STANDARD_FEATURE_NAMES.each_with_index.to_h do |feature_name, index|
    [feature_name, index + 1]
  end.freeze

  FEATURES = FEATURE_LIST.each_with_index.each_with_object({}) do |(feature, index), result|
    next if index >= MAX_BIGINT_FEATURE_FLAGS

    result[index + 1] = "feature_#{feature['name']}".to_sym
  end

  included do
    include FlagShihTzu
    has_flags FEATURES.merge(column: 'feature_flags').merge(QUERY_MODE)

    after_initialize :normalize_feature_flags_type
    before_create :enable_default_features

    FEATURE_LIST.each do |feature|
      feature_name = feature['name']

      define_method("feature_#{feature_name}?") do
        feature_enabled?(feature_name)
      end

      define_method("feature_#{feature_name}=") do |enabled|
        if ActiveModel::Type::Boolean.new.cast(enabled)
          enable_features(feature_name)
        else
          disable_features(feature_name)
        end
      end
    end

    define_method(:selected_feature_flags=) do |features|
      assign_selected_feature_flags(features)
    end

    define_method(:selected_feature_flags) do
      selected_feature_flags_list
    end
  end

  def enable_features(*names)
    names.each do |name|
      feature_name = normalize_feature_name(name)
      if overflow_feature?(feature_name)
        set_overflow_feature(feature_name, true)
      else
        set_standard_feature(feature_name, true)
      end
    end
  end

  def enable_features!(*names)
    enable_features(*names)
    save
  end

  def disable_features(*names)
    names.each do |name|
      feature_name = normalize_feature_name(name)
      if overflow_feature?(feature_name)
        set_overflow_feature(feature_name, false)
      else
        set_standard_feature(feature_name, false)
      end
    end
  end

  def disable_features!(*names)
    disable_features(*names)
    save
  end

  def feature_enabled?(name)
    feature_name = normalize_feature_name(name)
    return overflow_feature_enabled?(feature_name) if overflow_feature?(feature_name)

    standard_feature_enabled?(feature_name)
  end

  def assign_selected_feature_flags(features)
    feature_names = Array(features).map { |feature| normalize_feature_name(feature) }.uniq
    overflow_features, standard_features = feature_names.partition { |feature_name| overflow_feature?(feature_name) }

    self.internal_attributes ||= {}
    internal_attributes[OVERFLOW_FEATURE_ATTRIBUTE] = overflow_features

    self[:feature_flags] = build_standard_feature_flags_value(standard_features)
  end

  def selected_feature_flags_list
    FEATURE_LIST.each_with_object([]) do |feature, result|
      feature_name = feature['name']
      result << "feature_#{feature_name}" if feature_enabled?(feature_name)
    end
  end

  def all_features
    FEATURE_LIST.pluck('name').index_with do |feature_name|
      feature_enabled?(feature_name)
    end
  end

  def enabled_features
    all_features.select { |_feature, enabled| enabled == true }
  end

  def disabled_features
    all_features.select { |_feature, enabled| enabled == false }
  end

  private

  def normalize_feature_name(name)
    name.to_s.delete_prefix('feature_')
  end

  def overflow_feature?(feature_name)
    OVERFLOW_FEATURE_NAMES.include?(feature_name)
  end

  def overflow_feature_flags
    Array(internal_attributes&.dig(OVERFLOW_FEATURE_ATTRIBUTE)).map(&:to_s)
  end

  def overflow_feature_enabled?(feature_name)
    overflow_feature_flags.include?(feature_name)
  end

  def set_overflow_feature(feature_name, enabled)
    updated_features = overflow_feature_flags

    if enabled
      updated_features << feature_name unless updated_features.include?(feature_name)
    else
      updated_features.delete(feature_name)
    end

    self.internal_attributes ||= {}
    internal_attributes[OVERFLOW_FEATURE_ATTRIBUTE] = updated_features
  end

  def ensure_standard_feature_flags_integer!
    return if self[:feature_flags].is_a?(Integer) || self[:feature_flags].nil?

    self[:feature_flags] = self[:feature_flags].to_i
  end

  def normalize_feature_flags_type
    ensure_standard_feature_flags_integer!
  end

  def standard_feature_enabled?(feature_name)
    bit_position = STANDARD_FEATURE_POSITIONS[feature_name]
    return false if bit_position.nil?

    (standard_feature_flags_value & feature_bit_mask(bit_position)).positive?
  end

  def set_standard_feature(feature_name, enabled)
    bit_position = STANDARD_FEATURE_POSITIONS[feature_name]
    return if bit_position.nil?

    feature_mask = feature_bit_mask(bit_position)
    current_value = standard_feature_flags_value

    self[:feature_flags] = if enabled
                             current_value | feature_mask
                           else
                             current_value & ~feature_mask
                           end
  end

  def build_standard_feature_flags_value(feature_names)
    feature_names.reduce(0) do |result, feature_name|
      bit_position = STANDARD_FEATURE_POSITIONS[feature_name]
      next result if bit_position.nil?

      result | feature_bit_mask(bit_position)
    end
  end

  def feature_bit_mask(bit_position)
    1 << (bit_position - 1)
  end

  def standard_feature_flags_value
    self[:feature_flags].to_i
  end

  def enable_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return true if config.blank?

    features_to_enabled = config.value.select { |f| f[:enabled] }.pluck(:name)
    enable_features(*features_to_enabled)
  end
end
