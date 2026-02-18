attachments = canned_response.files.attachments
json.id canned_response.id
json.short_code canned_response.short_code
json.content canned_response.content
json.content_type canned_response.content_type
json.account_id canned_response.account_id
json.custom_role_id canned_response.custom_role_id
json.files canned_response.file_base_data if attachments.any?
