# Integración nativa n8n en Chatwoot

Este módulo elimina la necesidad del servidor Node.js intermedio y permite que Chatwoot orqueste directamente flujos de n8n.

## Modo recomendado: Agent Bot sin automatizaciones

Puedes habilitar un bot por inbox y marcarlo como "n8n nativo" para que Chatwoot gestione el flujo sin reglas de automatización.

1) Crea/edita un Agent Bot y define:
  - outgoing_url: URL completa del webhook de inicio de n8n (ej: `https://n8n.ejemplo.com/webhook/<ID>`)
  - bot_config (JSON). Los toggles disponibles permiten definir qué eventos arrancan el flujo:
    - `n8n_start_on_message`: Dispara al primer mensaje entrante de la conversación (si aún no existe flujo). Está habilitado por defecto y fuerza que la conversación pase a `pending` antes de orquestar el flujo.
    - `n8n_start_on_manual_pending`: Dispara cuando un agente marca la conversación como pendiente.
    - `n8n_start_on_contact_pending`: Dispara cuando un mensaje del cliente reabre la conversación y la deja en pendiente.
    - `n8n_restart_on_reopen`: Si está activo, reinicia el flujo cuando la conversación sale de pendiente y vuelve a ese estado.
    - `n8n_start_on_conversation_created`: Opcional; inicia el flujo tan pronto se crea la conversación.

2) Asocia el Agent Bot al inbox y actívalo.

Qué hace Chatwoot cuando `n8n_native` está activo:
- message_created (entrante de Contact):
  - Si la conversación no tiene `flow_id`, la mueve automáticamente a `pending`, inicia el flujo llamando a `outgoing_url` y persiste el `flow_id` devuelto.
  - Si ya hay `flow_id` y la conversación sigue en `pending`, **intenta** reenviar el mensaje a `https://<host>/webhook-waiting/<flow_id>`.
    - Si el flujo de n8n NO está esperando input (no tiene nodo "Wait for Webhook"), el reenvío fallará silenciosamente.
    - El flujo NO se reinicia automáticamente - mantiene el `flow_id` para evitar crear flujos duplicados.
    - Para que un flujo procese mensajes del cliente, debe incluir nodos "Wait for Webhook" en n8n.
- conversation_opened: resetea el `flow_id` para permitir reinicio de flujo.
- conversation_created (opcional si `n8n_start_on_conversation_created=true`): inicia el flujo incluso antes del primer mensaje.

### Estado de la conversación
Los flujos n8n sólo se inician o reenvían cuando la conversación está en estado `pending`. Si la conversación aún no está en `pending` y se cumple la condición `n8n_start_on_message`, Chatwoot la moverá automáticamente a ese estado para garantizar que el flujo arranque con la semántica correcta. El propio flujo debe actualizar el estado a otro valor cuando finalice; si posteriormente se vuelve a marcar como `pending`, Chatwoot solicitará un nuevo `flow_id` y reiniciará el flujo desde `outgoing_url`.
Se recomienda que el workflow de n8n cambie el estado a `open`, `resolved` o cualquier otro estado distinto de `pending` al completar sus acciones.

### Flujos que no esperan respuesta del usuario
Si tu flujo de n8n **solo envía mensajes** sin esperar input del cliente (no tiene nodos "Wait for Webhook"), debes configurarlo para que cambie el estado de la conversación al finalizar:

1. Usa el nodo HTTP Request de n8n para llamar al API de Chatwoot
2. Cambia el estado de la conversación a `open` o `resolved`
3. Endpoint: `PATCH /api/v1/accounts/{account_id}/conversations/{conversation_id}`
4. Body: `{"status": "resolved"}` o `{"status": "open"}`

**Comportamiento cuando el cliente envía mensajes durante un flujo activo:**
- Si el flujo NO tiene "Wait for Webhook": el mensaje se intenta enviar a n8n, falla silenciosamente, y el flujo continúa normalmente.
- Si el flujo SÍ tiene "Wait for Webhook": el mensaje se envía correctamente y el flujo lo procesa.
- En ambos casos, el `flow_id` se mantiene para evitar crear flujos duplicados.
- El flujo original debe cambiar el estado de la conversación para liberar el control del bot.

### Retrys y robustez HTTP
La orquestación incluye:
- Timeout de 8s en cada POST.
- Retries exponenciales (3 intentos, esperas: 0s, 0.25s, 0.5s aprox) ante errores de red o códigos != 2xx.
- Derivación de la URL `webhook-waiting` preservando subpath (soporta instalaciones en subcarpetas).

### Campos internos
- `conversations.assignee_agent_bot_id` indica qué bot nativo controla la conversación mientras el flujo está activo.
- `n8n_flows.flow_id` se persiste con el identificador devuelto por n8n y sirve para derivar el endpoint `webhook-waiting`.
- `last_message_id` se obtiene tanto de payloads con `id` directo como de `messages[0].id`.

### Sugerencias de endurecimiento adicional (opcionales)
1. Añadir verificación de firma HMAC si n8n devuelve respuesta firmada.
2. Guardar último HTTP code y cuerpo para auditoría (`last_http_code`, `last_http_error`).
3. Implementar transición automática a `waiting` si la respuesta incluye clave específica (ej: `{ "status": "waiting" }`).
4. Circuit breaker simple: si 5 fallos consecutivos → desactivar el bot temporalmente o etiquetar la conversación como `n8n_error`.
5. Métricas: contador de inicios, reintentos y fallos para visualización futura.

### Ejemplo de bot_config avanzado
```json
{
  "n8n_native": true,
  "n8n_start_on_conversation_created": true,
  "n8n_start_on_message": true,
  "n8n_start_on_manual_pending": true,
  "n8n_start_on_contact_pending": false,
  "n8n_restart_on_reopen": false
}
```

### Inicio por cambio de estado a pending
El flujo ahora se inicia preferentemente cuando la conversación cambia su estado a `pending` (evento `conversation_updated` con cambio real de `status`). Puedes granularlo desde `bot_config`:

- `n8n_start_on_manual_pending`: controla si se dispara cuando un agente marca la conversación como pendiente.
- `n8n_start_on_contact_pending`: controla si se dispara cuando un mensaje del cliente reabre la conversación y la plataforma la mueve a `pending`.

Comportamiento:
1. Cambio a `pending` desde cualquier otro estado → inicia o reinicia el flujo (usa `outgoing_url`). Incluso si quedó un `flow_id` residual, Chatwoot lo limpia automáticamente antes de arrancar el nuevo flujo.
2. Mensajes mientras está en `pending` → sólo se envían a `webhook-waiting/<flow_id>` (no crean nuevos flujos). Si la conversación abandonó `pending`, los mensajes no se reenvían hasta que vuelva a ese estado.
3. Reapertura (`conversation_opened`) con estado permitido → `reset_flow` (limpia `flow_id`).
4. Inicio por mensaje directo sólo ocurre si `"n8n_start_on_message": true`, no hay flujo activo y es el primer mensaje entrante.

Esto evita múltiples ejecuciones simultáneas al permanecer la conversación en `pending`.


Notas
- No se usa `.env` para n8n; el dominio/URL viene del `outgoing_url` del bot, por lo que puedes usar múltiples dominios/configs por inbox/bot.
- El `waiting` endpoint se deriva automáticamente de la URL de inicio: `<scheme>://<host[:port]>/webhook-waiting/<flow_id>`.
- Los endpoints públicos de automatización fueron retirados; migra cualquier regla de automatización a bots nativos antes de actualizar.

## Esquema de datos

Tabla `n8n_flows` (1-a-1 con `conversations`):
- conversation_id (unique)
- flow_id (string)
- last_message_id (bigint)
- flow_webhook_url (string)
- last_triggered_at (datetime)

Relación adicional:
- conversations.assignee_agent_bot_id (bigint, nullable)

## Variables de entorno

- No se requieren variables adicionales; cada bot define su propio `outgoing_url`.

## Migración

Ejecuta las migraciones habituales de Rails para crear la tabla:

- `bundle exec rails db:migrate`

## Notas

- Cada nueva transición a `pending` solicita un `flow_id` fresco mediante `outgoing_url`; los mensajes entrantes se reenvían a `webhook-waiting/:flow_id` mientras n8n mantenga la ejecución en espera.
- Cuando la conversación abandona `pending`, Chatwoot limpia el `flow_id` y libera la asignación del bot nativo. Si vuelve a `pending`, se creará una nueva ejecución automáticamente.
- Este módulo no requiere autenticación en los endpoints públicos; mantén las URLs internas/privadas.
