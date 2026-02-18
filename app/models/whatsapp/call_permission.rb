# frozen_string_literal: true

# Namespaced wrapper for WhatsApp call permissions to match services and specs
class Whatsapp::CallPermission < WhatsappCallPermission
  self.table_name = 'whatsapp_call_permissions'
end
