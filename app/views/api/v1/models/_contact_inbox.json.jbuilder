json.source_id resource.source_id

# Some contact_inboxes may reference a deleted inbox; skip rendering inbox data to avoid nil errors
if resource.inbox.present?
  json.inbox do
    json.partial! 'api/v1/models/inbox_slim', formats: [:json], resource: resource.inbox
  end
else
  json.inbox nil
end
