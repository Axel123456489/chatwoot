# == Schema Information
#
# Table name: whatsapp_message_errors
#
#  id            :bigint           not null, primary key
#  error_message :text
#  error_type    :string           not null
#  raw_payload   :json             not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class WhatsappMessageError < ApplicationRecord
  # Guarda el payload y el error de mensajes no procesados
  validates :raw_payload, presence: true
  validates :error_type, presence: true
end
