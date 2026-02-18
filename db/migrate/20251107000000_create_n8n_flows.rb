class CreateN8nFlows < ActiveRecord::Migration[7.0]
  def change
    create_table :n8n_flows do |t|
      t.bigint :conversation_id, null: false
      t.string :flow_id
      t.string :flow_status, default: 'pending', null: false
      t.boolean :reserving_flow, default: false, null: false
      t.bigint :last_message_id
      t.string :flow_webhook_url
      t.datetime :last_triggered_at

      t.timestamps
    end

    add_index :n8n_flows, :conversation_id, unique: true
    add_foreign_key :n8n_flows, :conversations
  end
end
