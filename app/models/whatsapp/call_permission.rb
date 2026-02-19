# frozen_string_literal: true

# == Schema Information
#
# Table name: whatsapp_call_permissions
#
#  id                   :bigint           not null, primary key
#  expires_at           :datetime
#  granted_at           :datetime
#  metadata             :jsonb
#  permission_status    :string           default("pending"), not null
#  remaining_calls      :integer          default(10), not null
#  requested_at         :datetime
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  contact_id           :bigint           not null
#  inbox_id             :bigint
#  phone_number_id      :string           not null
#  requested_by_user_id :bigint
#  whatsapp_message_id  :string
#
# Indexes
#
#  index_whatsapp_call_permissions_on_account_id             (account_id)
#  index_whatsapp_call_permissions_on_contact_id             (contact_id)
#  index_whatsapp_call_permissions_on_inbox_id               (inbox_id)
#  index_whatsapp_call_permissions_on_permission_status      (permission_status)
#  index_whatsapp_call_permissions_on_requested_by_user_id   (requested_by_user_id)
#  index_whatsapp_call_perms_on_account_contact_phone_inbox  (account_id,contact_id,phone_number_id,inbox_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (requested_by_user_id => users.id)
#
# Namespaced wrapper for WhatsApp call permissions to match services and specs
class Whatsapp::CallPermission < WhatsappCallPermission
  self.table_name = 'whatsapp_call_permissions'
end
