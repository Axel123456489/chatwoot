json.payload do
  json.array! @templates do |template|
    json.id template[:id]
    json.name template[:name]
    json.category template[:category]
    json.channel_type template[:channel_type]
    json.content template[:content]
    json.content_type template[:content_type]
    json.language template[:language]
    json.status template[:status]
    json.components template[:components]
    json.meta template[:meta]
    json.created_at template[:created_at]
    json.updated_at template[:updated_at]
    json.inbox_id template[:inbox_id]
    json.inbox_name template[:inbox_name]
  end
end

json.meta do
  json.total_entries @total_count
  json.current_page (params[:page] || 1).to_i
  json.per_page 10
end
