class CreateWhatsappMessageErrors < ActiveRecord::Migration[6.1]
  def change
    create_table :whatsapp_message_errors do |t|
      t.json :raw_payload, null: false
      t.string :error_type, null: false
      t.text :error_message
      t.timestamps
    end
  end
end
