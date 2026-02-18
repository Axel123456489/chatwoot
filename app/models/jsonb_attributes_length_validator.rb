class JsonbAttributesLengthValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.empty?

    @attribute = attribute
    @record = record

    value.each do |key, attribute_value|
      validate_keys(key, attribute_value)
    end
  end

  def validate_keys(key, attribute_value)
    case attribute_value.class.name
    when 'String'
      @record.errors.add @attribute, "#{key} length should be < 1500" if attribute_value.length > 1500
    when 'Integer'
      max_value = 9_999_999_999
      @record.errors.add @attribute, "#{key} value should be < #{max_value}" if attribute_value > max_value
    end
  end
end
