class WhatsappMessageError < ApplicationRecord
  # Guarda el payload y el error de mensajes no procesados
  validates :raw_payload, presence: true
  validates :error_type, presence: true
end
