# frozen_string_literal: true

class UpdateWhatsappCallPermissions < ActiveRecord::Migration[7.1]
  def change
    add_reference :whatsapp_call_permissions, :inbox, foreign_key: true unless column_exists?(:whatsapp_call_permissions, :inbox_id)

    add_column :whatsapp_call_permissions, :requested_at, :datetime unless column_exists?(:whatsapp_call_permissions, :requested_at)

    unless column_exists?(:whatsapp_call_permissions, :requested_by_user_id)
      add_reference :whatsapp_call_permissions, :requested_by_user, foreign_key: { to_table: :users }
    end

    add_column :whatsapp_call_permissions, :whatsapp_message_id, :string unless column_exists?(:whatsapp_call_permissions, :whatsapp_message_id)

    if index_exists?(:whatsapp_call_permissions, [:account_id, :contact_id, :phone_number_id],
                     name: 'index_whatsapp_call_perms_on_account_contact_phone')
      remove_index :whatsapp_call_permissions,
                   column: %i[account_id contact_id phone_number_id],
                   name: 'index_whatsapp_call_perms_on_account_contact_phone'
    end

    unless index_exists?(:whatsapp_call_permissions, [:account_id, :contact_id, :phone_number_id, :inbox_id],
                         name: 'index_whatsapp_call_perms_on_account_contact_phone_inbox')
      add_index :whatsapp_call_permissions, [:account_id, :contact_id, :phone_number_id, :inbox_id],
                name: 'index_whatsapp_call_perms_on_account_contact_phone_inbox', unique: true
    end
  end
end
