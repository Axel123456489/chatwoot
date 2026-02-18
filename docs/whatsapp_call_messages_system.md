# WhatsApp Call Messages System

Sistema completo para manejar mensajes de llamadas de WhatsApp como marcas de tiempo en el historial de conversaciones.

## Características

### 1. Llamadas Contestadas (Flujo Exitoso)

```
┌─────────────────────────────────────────────────────────┐
│  TIMELINE DE LLAMADA CONTESTADA                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  [📲 Call initiated...] ← Primera marca                 │
│  10:30 AM • Outgoing call                               │
│                                                          │
│  [Mensaje normal del agente]                            │
│  10:31 AM • "¿Puedes escucharme?"                       │
│                                                          │
│  [☎️ Connected • 02:15] ← Segunda marca (conectado)     │
│  10:31 AM • Call duration updating                      │
│                                                          │
│  [Mensajes normales durante la llamada]                 │
│  10:32 AM • "Te envío el enlace por aquí"              │
│                                                          │
│  [📞 Call ended • 05:42] ← Tercera marca (fin)         │
│  10:35 AM • Outgoing call                               │
│  🎙️ Recording attached (audio player)                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Estados del flujo exitoso:**
- `call_initiated`: Primera marca cuando se inicia la llamada
- `call_connected`: Segunda marca cuando el usuario contesta
- `call_completed`: Tercera marca cuando termina, CON grabación adjunta

### 2. Llamadas No Contestadas (Múltiples Formatos)

#### a) Call Rejected (Rechazada)
```
[🚫 Call rejected]
10:30 AM • Outgoing call
User declined the call
```

#### b) Call Missed (Perdida/No contestada)
```
[📵 Missed call]
10:30 AM • Outgoing call  
User did not answer
```

#### c) Call Cancelled (Cancelada por el caller)
```
[❌ Call cancelled]
10:30 AM • Outgoing call
Cancelled before answer
```

#### d) Call Busy (Usuario ocupado)
```
[📵 User busy]
10:30 AM • Outgoing call
User was on another call
```

#### e) Call No Connection (Fallo de conexión)
```
[📡 Connection failed]
10:30 AM • Outgoing call
Network error or connectivity issue
```

#### f) Call Failed (Fallo genérico)
```
[⚠️ Call failed]
10:30 AM • Outgoing call
Unknown error occurred
```

### 3. Errores de Meta API

Los errores de Meta WhatsApp API se manejan de forma similar a los errores de mensajes:

#### a) Not Authorized (No autorizado)
```
[⚠️ Error: Not authorized]
10:30 AM • Outgoing call
❗ WhatsApp Business account not authorized for calling

Error code: 190
```

#### b) Insufficient Balance (Sin saldo)
```
[⚠️ Error: Insufficient balance]
10:30 AM • Outgoing call
❗ Your account does not have enough balance to make calls

Error code: 131031
```

#### c) Calling Not Enabled (No habilitado)
```
[⚠️ Error: Calling not enabled]
10:30 AM • Outgoing call
❗ Calling feature is not enabled for this WhatsApp number

Error code: 131047
```

#### d) Rate Limit (Límite de tasa)
```
[⚠️ Error: Rate limit exceeded]
10:30 AM • Outgoing call
❗ Too many calls. Please try again later

Error code: 4
```

#### e) Invalid Parameters (Parámetros inválidos)
```
[⚠️ Error: Invalid parameters]
10:30 AM • Outgoing call
❗ Invalid phone number or call parameters

Error code: 131056
```

## Estructura de Datos

### Migración: `AddWhatsappCallFieldsToMessages`

```ruby
add_column :messages, :call_metadata, :jsonb, default: {}
add_column :messages, :call_status, :integer
add_column :messages, :call_duration, :integer # en segundos
```

### Call Status Enum

```ruby
enum call_status: {
  # Exitosas
  call_initiated: 0,
  call_connected: 1,
  call_completed: 2,
  
  # No exitosas
  call_rejected: 10,
  call_missed: 11,
  call_cancelled: 12,
  call_busy: 13,
  call_no_connection: 14,
  call_failed: 15,
  
  # Errores de Meta
  call_error_unauthorized: 20,
  call_error_no_balance: 21,
  call_error_not_enabled: 22,
  call_error_rate_limit: 23,
  call_error_invalid: 24
}
```

### Call Metadata (JSON)

```json
{
  "call_id": "call-abc123",
  "call_direction": "outbound",
  "whatsapp_call_sid": "wa-call-456def",
  "initiated_at": 1703674200,
  "connected_at": 1703674205,
  "ended_at": 1703674547,
  "recording_url": "https://...",
  "recording_duration": 342,
  "error_code": null,
  "error_message": null
}
```

## Uso del Sistema

### 1. Crear Mensaje de Llamada Iniciada

```ruby
builder = Whatsapp::Calling::CallMessageBuilder.new(
  conversation: conversation,
  whatsapp_call: whatsapp_call
)

message = builder.create_initiated_message
# Retorna: Message con call_status: :call_initiated
```

### 2. Actualizar a Llamada Conectada

```ruby
message = builder.create_connected_message
# Retorna: Message con call_status: :call_connected
```

### 3. Finalizar Llamada con Grabación

```ruby
# Crear attachment de grabación
recording = conversation.messages.build.attachments.build(
  file_type: :audio,
  account_id: account.id
)
recording.file.attach(
  io: File.open(recording_path),
  filename: 'recording.mp3',
  content_type: 'audio/mpeg'
)
recording.save!

# Crear mensaje final
message = builder.create_completed_message(
  recording_attachment: recording
)
# Retorna: Message con call_status: :call_completed + attachment
```

### 4. Manejar Llamada No Contestada

```ruby
message = builder.create_failed_message(
  reason: 'missed', # o 'rejected', 'cancelled', 'busy', 'no_connection'
  error_code: nil,
  error_message: nil
)
```

### 5. Manejar Error de Meta API

```ruby
message = builder.create_meta_error_message(
  error_code: 131031,
  error_message: 'Insufficient account balance',
  meta_response: { ... } # respuesta completa de Meta
)
```

## Mapeo de Errores de Meta

El sistema automáticamente mapea códigos de error de Meta a estados de llamada:

```ruby
Meta Error Code → Call Status
─────────────────────────────
100, 190        → call_error_unauthorized
2, 4, 17        → call_error_rate_limit
131031, 131032  → call_error_no_balance
131047-131049   → call_error_not_enabled
131056          → call_error_invalid
*               → call_failed
```

## API Response

Cuando se consultan mensajes de llamada, incluyen:

```json
{
  "id": 12345,
  "content": "Call ended • 05:42",
  "message_type": "outgoing",
  "content_type": "voice_call",
  "call_status": "call_completed",
  "call_duration": 342,
  "call_metadata": {
    "call_id": "call-abc123",
    "call_direction": "outbound",
    "initiated_at": 1703674200,
    "connected_at": 1703674205,
    "ended_at": 1703674547,
    "recording_duration": 342
  },
  "attachments": [
    {
      "id": 789,
      "file_type": "audio",
      "data_url": "https://...",
      "extension": "mp3"
    }
  ],
  "call_info": {
    "status_icon": "📞",
    "status_message": "Call ended • 05:42",
    "formatted_duration": "05:42",
    "has_recording": true,
    "is_successful": true,
    "is_failed": false,
    "is_meta_error": false
  }
}
```

## Componente Vue

El componente `WhatsAppCallMessage.vue` renderiza estos mensajes con:

- **Color coding**: Verde (exitosa), Rojo (error Meta), Amarillo (fallida), Gris (pendiente)
- **Iconos**: Específicos para cada estado
- **Player de audio**: Para grabaciones
- **Timeline**: Muestra hora de inicio, conexión y fin
- **Mensajes de error**: Detallados para errores de Meta

## Beneficios

1. **No envía mensajes de texto**: Los mensajes de llamada son solo marcadores locales
2. **Historial claro**: Timeline visual de llamadas en la conversación
3. **Grabaciones integradas**: Audio player inline para escuchar grabaciones
4. **Manejo robusto de errores**: Estados específicos para cada tipo de fallo
5. **Compatibilidad con Meta**: Mapeo automático de códigos de error
6. **UX mejorada**: Contexto completo de cada llamada sin interrumpir el flujo

## Scopes Útiles

```ruby
# Obtener todas las llamadas de una conversación
conversation.messages.call_messages

# Obtener solo llamadas completadas con grabación
conversation.messages.completed_calls

# Obtener llamadas fallidas
conversation.messages.failed_calls

# Obtener llamadas exitosas
conversation.messages.successful_calls

# Buscar por call_id
Message.where("call_metadata->>'call_id' = ?", 'call-abc123')
```

## Testing

```ruby
# Spec helpers
let(:call_message) do
  create(:message, 
    content_type: :voice_call,
    call_status: :call_completed,
    call_duration: 342,
    call_metadata: {
      call_id: 'test-123',
      call_direction: 'outbound',
      recording_duration: 342
    }
  )
end

expect(call_message.voice_call?).to be true
expect(call_message.call_successful?).to be true
expect(call_message.formatted_call_duration).to eq '05:42'
```
