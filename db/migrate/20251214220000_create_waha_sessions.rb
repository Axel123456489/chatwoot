# frozen_string_literal: true

class CreateWahaSessions < ActiveRecord::Migration[7.0]
  def change
    return if table_exists?(:waha_sessions)

    create_table :waha_sessions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.string :session_name, null: false
      t.string :status, default: 'pending', null: false
      t.string :phone_number
      t.text :qr_code
      t.datetime :qr_code_generated_at
      t.jsonb :waha_data, default: {}

      t.timestamps
    end

    add_index :waha_sessions, :session_name, unique: true
    add_index :waha_sessions, :status
    add_index :waha_sessions, %i[account_id inbox_id], unique: true
  end
end
