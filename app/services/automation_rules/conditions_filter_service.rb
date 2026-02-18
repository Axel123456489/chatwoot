require 'json'

class AutomationRules::ConditionsFilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(rule, conversation = nil, options = {})
    super([], nil)
    # assign rule, conversation and account to instance variables
    @rule = rule
    @conversation = conversation
    @account = conversation.account

    # setup filters from json file
    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)

    @conversation_filters = @filters['conversations']
    @contact_filters = @filters['contacts']
    @message_filters = @filters['messages']

    @options = options
    @changed_attributes = options[:changed_attributes]
  end

  def perform
    Rails.logger.info("[Automation][Conditions] Evaluating rule_id=#{@rule.id} conversation_id=#{@conversation.id} conditions=#{@rule.conditions.inspect}")
    return false unless rule_valid?

    @attribute_changed_query_filter = []

    @rule.conditions.each_with_index do |query_hash, current_index|
      @attribute_changed_query_filter << query_hash and next if query_hash['filter_operator'] == 'attribute_changed'

      apply_filter(query_hash, current_index)
    end

    # When there are no non-attribute_changed filters, avoid calling where with an empty query string
    records = if @query_string.present?
                base_relation.where(@query_string, @filter_values.with_indifferent_access)
              else
                base_relation
              end
    records = perform_attribute_changed_filter(records) if @attribute_changed_query_filter.any?

    result = records.any?
    Rails.logger.info("[Automation][Conditions] result=#{result} rule_id=#{@rule.id} conversation_id=#{@conversation.id}")
    result
  rescue StandardError => e
    Rails.logger.error "Error in AutomationRules::ConditionsFilterService: #{e.message}"
    Rails.logger.info "AutomationRules::ConditionsFilterService failed while processing rule #{@rule.id} for conversation #{@conversation.id}"
    false
  end

  def rule_valid?
    is_valid = AutomationRules::ConditionValidationService.new(@rule).perform
    Rails.logger.info "Automation rule condition validation failed for rule id: #{@rule.id}" unless is_valid
    @rule.authorization_error! unless is_valid

    is_valid
  end

  def filter_operation(query_hash, current_index)
    if query_hash[:filter_operator] == 'starts_with'
      @filter_values["value_#{current_index}"] = "#{string_filter_values(query_hash)}%"
      like_filter_string(query_hash[:filter_operator], current_index)
    else
      super
    end
  end

  def apply_filter(query_hash, current_index)
    conversation_filter = @conversation_filters[query_hash['attribute_key']]
    contact_filter = @contact_filters[query_hash['attribute_key']]
    message_filter = @message_filters[query_hash['attribute_key']]

    if conversation_filter
      @query_string += conversation_query_string('conversations', conversation_filter, query_hash.with_indifferent_access, current_index)
    elsif contact_filter
      @query_string += contact_query_string(contact_filter, query_hash.with_indifferent_access, current_index)
    elsif message_filter
      @query_string += message_query_string(message_filter, query_hash.with_indifferent_access, current_index)
    elsif custom_attribute(query_hash['attribute_key'], @account, query_hash['custom_attribute_type'])
      # send table name according to attribute key right now we are supporting contact based custom attribute filter
      @query_string += custom_attribute_query(query_hash.with_indifferent_access, query_hash['custom_attribute_type'], current_index)
    end
  end

  # If attribute_changed type filter is present perform this against array
  def perform_attribute_changed_filter(records)
    return [] if @changed_attributes.blank?

    @attribute_changed_records = []
    current_attribute_changed_record = base_relation
    filter_based_on_attribute_change(records, current_attribute_changed_record)

    @attribute_changed_records.uniq
  end

  # Loop through attribute_changed_query_filter
  def filter_based_on_attribute_change(records, current_attribute_changed_record)
    indifferent_changed_attrs = @changed_attributes.with_indifferent_access
    @attribute_changed_query_filter.each do |filter|
      attr_key = normalized_attribute_key(filter['attribute_key'])
      pair = extract_attribute_change_pair(indifferent_changed_attrs, attr_key)

      if pair.present?
        from_val, to_val = pair
        from_values = normalize_filter_values_for(attr_key, filter['values']['from'])
        to_values = normalize_filter_values_for(attr_key, filter['values']['to'])

        matches = if attr_key == 'label_list'
                    prev_labels = Array(from_val).map(&:to_s)
                    curr_labels = Array(to_val).map(&:to_s)
                    # Detect special sentinels and wildcard cases
                    from_none_selected = from_values.any? { |v| v.is_a?(Array) && v.empty? }
                    to_none_selected = to_values.any? { |v| v.is_a?(Array) && v.empty? }
                    from_wildcard = from_values.empty?
                    to_wildcard = to_values.empty?

                    from_match = if from_wildcard
                                   true
                                 elsif from_none_selected
                                   prev_labels.empty?
                                 else
                                   prev_labels.intersect?(from_values)
                                 end

                    to_match = if to_wildcard
                                 true
                               elsif to_none_selected
                                 curr_labels.empty?
                               else
                                 curr_labels.intersect?(to_values)
                               end

                    Rails.logger.info("[Automation][Conditions] label_change prev=#{prev_labels} curr=#{curr_labels} from_values=#{from_values} to_values=#{to_values} from_wildcard=#{from_wildcard} to_wildcard=#{to_wildcard} from_none_selected=#{from_none_selected} to_none_selected=#{to_none_selected} from_match=#{from_match} to_match=#{to_match}")
                    from_match && to_match
                  else
                    from_values.include?(from_val) && to_values.include?(to_val)
                  end

        @attribute_changed_records = attribute_changed_filter_query(filter, records, current_attribute_changed_record) if matches
      end
      current_attribute_changed_record = @attribute_changed_records
    end
  end

  # We intersect with the record if query_operator-AND is present and union if query_operator-OR is present
  def attribute_changed_filter_query(filter, records, current_attribute_changed_record)
    op = filter['query_operator'].to_s.upcase
    if op == 'AND'
      @attribute_changed_records + (current_attribute_changed_record & records)
    else
      @attribute_changed_records + (current_attribute_changed_record | records)
    end
  end

  def message_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']

    attribute_key = 'processed_message_content' if attribute_key == 'content'

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'standard'
      if current_filter['data_type'] == 'text'
        " LOWER(messages.#{attribute_key}) #{filter_operator_value} #{query_operator} "
      else
        " messages.#{attribute_key} #{filter_operator_value} #{query_operator} "
      end
    end
  end

  # This will be used in future for contact automation rule
  def contact_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']

    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'additional_attributes'
      " contacts.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'standard'
      " contacts.#{attribute_key} #{filter_operator_value} #{query_operator} "
    end
  end

  def conversation_query_string(table_name, current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']
    filter_operator_value = filter_operation(query_hash, current_index)

    case current_filter['attribute_type']
    when 'additional_attributes'
      " #{table_name}.additional_attributes ->> '#{attribute_key}' #{filter_operator_value} #{query_operator} "
    when 'standard'
      if attribute_key == 'labels'
        # Reuse the generic tag filter to support label conditions without explicit JOINs
        " #{tag_filter_query(query_hash, current_index)} "
      else
        " #{table_name}.#{attribute_key} #{filter_operator_value} #{query_operator} "
      end
    end
  end

  # Provide filter_config so tag_filter_query knows which entity/table to use
  def filter_config
    {
      entity: 'Conversation',
      table_name: 'conversations'
    }
  end

  private

  # Extracts [from, to] for a given attribute key from changed_attributes.
  # Supports:
  # - direct keys like 'status', 'assignee_id', etc.
  # - nested keys under 'custom_attributes' and 'additional_attributes'
  def extract_attribute_change_pair(changed_attrs, attribute_key)
    direct = changed_attrs[attribute_key]
    return direct if direct.is_a?(Array) && direct.size == 2

    # custom_attributes nested hash case
    if changed_attrs['custom_attributes'].is_a?(Array)
      old_h, new_h = changed_attrs['custom_attributes']
      if old_h.is_a?(Hash) && new_h.is_a?(Hash) && (old_h.key?(attribute_key) || new_h.key?(attribute_key))
        return [old_h[attribute_key], new_h[attribute_key]]
      end
    end

    # additional_attributes nested hash case
    if changed_attrs['additional_attributes'].is_a?(Array)
      old_h, new_h = changed_attrs['additional_attributes']
      if old_h.is_a?(Hash) && new_h.is_a?(Hash) && (old_h.key?(attribute_key) || new_h.key?(attribute_key))
        return [old_h[attribute_key], new_h[attribute_key]]
      end
    end

    nil
  end

  # Normalize attribute key names coming from filters to match changed_attributes keys
  # e.g., 'labels' filter maps to 'label_list' in previous_changes
  def normalized_attribute_key(key)
    return 'label_list' if key == 'labels'

    key
  end

  # Map enum names to integer values for comparison against previous_changes for enums
  def map_enum_value(attribute_key, value)
    return value if value.nil?

    case attribute_key
    when 'priority'
      # Conversation.priorities => { 'low' => 0, ... }
      Conversation.priorities[value.to_s] || value
    when 'status'
      Conversation.statuses[value.to_s] || value
    else
      # convert numeric-looking strings to integers to match DB values
      return value.to_i if value.is_a?(String) && value.match?(/\A-?\d+\z/)

      value
    end
  end

  def normalize_filter_values_for(attribute_key, values)
    key = normalized_attribute_key(attribute_key)
    vals = Array(values)

    if key == 'label_list'
      # Map None (sent as nil) to [] sentinel, and ensure strings for labels
      return vals.map { |v| v.nil? ? [] : v.to_s }
    end

    vals.map { |v| map_enum_value(key, v) }
  end

  def base_relation
    records = Conversation.where(id: @conversation.id).joins(
      'LEFT OUTER JOIN contacts on conversations.contact_id = contacts.id'
    ).joins(
      'LEFT OUTER JOIN messages on messages.conversation_id = conversations.id'
    )

    # Only add label joins when label conditions exist
    if label_conditions?
      records = records.joins(
        'LEFT OUTER JOIN taggings ON taggings.taggable_id = conversations.id AND taggings.taggable_type = \'Conversation\''
      ).joins(
        'LEFT OUTER JOIN tags ON taggings.tag_id = tags.id'
      )
    end

    records = records.where(messages: { id: @options[:message].id }) if @options[:message].present?
    records
  end

  def label_conditions?
    @rule.conditions.any? { |condition| condition['attribute_key'] == 'labels' }
  end
end
