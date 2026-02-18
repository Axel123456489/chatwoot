# frozen_string_literal: true

class CreateWhatsappCalling < ActiveRecord::Migration[7.1]
  def change
    # Channel config/flags
    add_column :channel_whatsapp, :calling_config, :jsonb, default: {} unless column_exists?(:channel_whatsapp, :calling_config)
    add_column :channel_whatsapp, :calling_enabled, :boolean, default: false unless column_exists?(:channel_whatsapp, :calling_enabled)

    # Permission tracking (required by WhatsApp calling)
    unless table_exists?(:whatsapp_call_permissions)
      create_table :whatsapp_call_permissions do |t|
        t.references :account, null: false, foreign_key: true, index: true
        t.references :contact, null: false, foreign_key: true, index: true
        t.string :phone_number_id, null: false
        t.string :permission_status, default: 'pending', null: false
        t.datetime :granted_at
        t.datetime :expires_at
        t.integer :remaining_calls, default: 10, null: false
        t.jsonb :metadata, default: {}

        t.timestamps
      end
    end

    unless index_exists?(:whatsapp_call_permissions, [:account_id, :contact_id, :phone_number_id],
                         name: 'index_whatsapp_call_perms_on_account_contact_phone')
      add_index :whatsapp_call_permissions, [:account_id, :contact_id, :phone_number_id],
                name: 'index_whatsapp_call_perms_on_account_contact_phone',
                unique: true
    end
    add_index :whatsapp_call_permissions, :permission_status unless index_exists?(:whatsapp_call_permissions, :permission_status)

    # Calls table
    unless table_exists?(:whatsapp_calls)
      create_table :whatsapp_calls do |t|
        t.references :account, null: false, foreign_key: true, index: true
        t.references :conversation, null: false, foreign_key: true, index: true
        t.references :contact, null: false, foreign_key: true, index: true
        t.references :inbox, null: false, foreign_key: true, index: true
        t.references :initiated_by_user, foreign_key: { to_table: :users }, index: true

        # WhatsApp call identifier
        t.string :call_id, null: false

        # Call details
        t.string :direction, null: false, limit: 20 # 'outbound' or 'inbound'
        t.string :status, null: false, limit: 30, default: 'initiated'
        t.string :status_reason, limit: 100

        # Timestamps
        t.datetime :initiated_at
        t.datetime :ringing_at
        t.datetime :accepted_at
        t.datetime :connected_at
        t.datetime :ended_at

        # Duration (in seconds)
        t.integer :duration_seconds

        # SDP information
        t.text :browser_sdp_offer
        t.text :whatsapp_sdp_answer

        # Additional metadata
        t.jsonb :metadata, default: {}
        t.jsonb :call_quality_metrics, default: {}

        # Recording
        t.string :recording_url
        t.boolean :recording_enabled, default: false

        # Inbound call handling
        t.bigint :accepted_by_user_id
        t.string :rejection_reason

        t.timestamps
      end
    end

    add_column :whatsapp_calls, :accepted_by_user_id, :bigint unless column_exists?(:whatsapp_calls, :accepted_by_user_id)
    add_column :whatsapp_calls, :rejection_reason, :string unless column_exists?(:whatsapp_calls, :rejection_reason)

    add_index :whatsapp_calls, :call_id, unique: true unless index_exists?(:whatsapp_calls, :call_id, unique: true)
    add_index :whatsapp_calls, [:account_id, :status] unless index_exists?(:whatsapp_calls, [:account_id, :status])
    add_index :whatsapp_calls, [:conversation_id, :created_at] unless index_exists?(:whatsapp_calls, [:conversation_id, :created_at])
    add_index :whatsapp_calls, [:contact_id, :created_at] unless index_exists?(:whatsapp_calls, [:contact_id, :created_at])
    add_index :whatsapp_calls, [:inbox_id, :created_at, :status] unless index_exists?(:whatsapp_calls, [:inbox_id, :created_at, :status])
    add_index :whatsapp_calls, :accepted_by_user_id unless index_exists?(:whatsapp_calls, :accepted_by_user_id)
    unless foreign_key_exists?(:whatsapp_calls, :users, column: :accepted_by_user_id)
      add_foreign_key :whatsapp_calls, :users, column: :accepted_by_user_id
    end

    # Message call metadata (used to link call lifecycle to activity messages)
    add_column :messages, :call_metadata, :jsonb, default: {} unless column_exists?(:messages, :call_metadata)
    add_column :messages, :call_status, :integer unless column_exists?(:messages, :call_status)
    add_column :messages, :call_duration, :integer, comment: 'Call duration in seconds' unless column_exists?(:messages, :call_duration)

    add_index :messages, :call_status unless index_exists?(:messages, :call_status)
    return if index_exists?(:messages, [:conversation_id, :content_type, :call_status], name: 'index_messages_on_conversation_call_status')

    add_index :messages, [:conversation_id, :content_type, :call_status],
              name: 'index_messages_on_conversation_call_status'
  end
end
