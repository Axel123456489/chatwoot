# Checklist de Implementación - Workflow Integrations

## ✅ Preparación (Completado)

- [x] Crear migraciones de base de datos (3 archivos)
- [x] Crear modelos (WorkflowIntegration, WorkflowExecution, N8n)
- [x] Crear servicios (WebhookPoster, TriggerDetector, PayloadBuilder, Executor)
- [x] Actualizar AgentBotListener
- [x] Crear WorkflowsController
- [x] Agregar rutas API
- [x] Documentar implementación

## ⏳ Ejecución (Pendiente)

### 1. Base de Datos

```bash
# Verificar conexión
psql -h localhost -U postgres -d chatwoot_dev -c "SELECT 1"
```

- [ ] PostgreSQL está corriendo
- [ ] Redis está corriendo
- [ ] Variables de entorno configuradas correctamente

### 2. Migraciones

```bash
cd /workspaces/ubuntu/chatwoot
bin/rails db:migrate
```

- [ ] Migración `create_workflow_integrations` ejecutada
- [ ] Migración `create_workflow_executions` ejecutada
- [ ] Migración `migrate_n8n_flows_to_workflow_executions` ejecutada
- [ ] Sin errores en output

### 3. Verificación

```bash
bin/rails console
```

```ruby
# Verificar tablas
> WorkflowIntegration.count
# Debe mostrar número de bots con n8n_native=true

> WorkflowExecution.count
# Debe mostrar número de registros migrados de n8n_flows

> WorkflowIntegrations::N8n.first
# Debe mostrar un registro con webhook_url, config, etc.

# Ver integraciones
> WorkflowIntegrations::N8n.all.each do |wi|
    puts "Bot: #{wi.agent_bot.name}"
    puts "URL: #{wi.webhook_url}"
    puts "Config: #{wi.config}"
    puts "---"
  end
```

- [ ] WorkflowIntegration tiene registros
- [ ] WorkflowExecution tiene registros históricos
- [ ] Configuraciones migradas correctamente

### 4. Pruebas Funcionales

#### A. Conversación Nueva

1. [ ] Crear conversación con inbox que tiene bot N8n
2. [ ] Enviar primer mensaje de contacto
3. [ ] Verificar en logs: `[N8n] Started execution_id=...`
4. [ ] Verificar en DB: `WorkflowExecution.last.status == 'running'`

#### B. Mensaje en Conversación Activa

1. [ ] Conversación con ejecución activa
2. [ ] Enviar nuevo mensaje
3. [ ] Verificar en logs: `[N8n] Forwarded message execution_id=...`
4. [ ] Verificar: `WorkflowExecution.last.last_activity_at` actualizado

#### C. Cancelación

```bash
curl -X POST "http://localhost:3000/api/v1/integrations/workflows/cancel_execution" \
  -H "Content-Type: application/json" \
  -d '{"conversation_id": <ID>}'
```

- [ ] Response 200 OK
- [ ] Execution.status == 'cancelled'
- [ ] Bot desasignado de conversación

#### D. Switch Execution

```bash
curl -X POST "http://localhost:3000/api/v1/integrations/workflows/switch_execution" \
  -H "Content-Type: application/json" \
  -d '{
    "conversation_id": <ID>,
    "execution_id": "test-flow-123"
  }'
```

- [ ] Response 200 OK
- [ ] Nueva execution creada
- [ ] Execution anterior cancelada

### 5. Logs y Monitoreo

```bash
tail -f log/development.log | grep -E "\[N8n\]|\[Workflows\]"
```

- [ ] Logs estructurados visibles
- [ ] Contexto completo (conversation_id, execution_id, trigger_type)
- [ ] Sin errores inesperados

### 6. Endpoints API

```bash
# Ver ejecuciones
curl "http://localhost:3000/api/v1/integrations/workflows/executions?conversation_id=<ID>"
```

- [ ] Lista de ejecuciones retornada
- [ ] JSON bien formateado
- [ ] Timestamps correctos

## 🔄 Rollback (Si es necesario)

```bash
# Deshacer migraciones
bin/rails db:rollback STEP=3
```

- [ ] Tabla `workflow_integrations` eliminada
- [ ] Tabla `workflow_executions` eliminada
- [ ] Datos en `n8n_flows` intactos

## 📊 Métricas a Monitorear

Durante las primeras 48h:

- [ ] Tasa de éxito de `start_execution` (>95%)
- [ ] Tiempo promedio de ejecución
- [ ] Errores de webhook (< 1%)
- [ ] Rate limits de N8n (429 responses)

## 🐛 Problemas Comunes

### Error: "No workflow integration found"

**Causa**: AgentBot no tiene WorkflowIntegration asociado

**Solución**:
```ruby
bot = AgentBot.find(<ID>)
WorkflowIntegrations::N8n.create!(
  agent_bot: bot,
  webhook_url: bot.bot_config['n8n_webhook_url'],
  status: :active,
  config: {
    start_on_new_conversation: true,
    start_on_reopen: true,
    start_on_manual_pending: true
  }
)
```

### Error: Webhook timeout

**Causa**: N8n no responde en 30s

**Solución**:
1. Verificar que N8n esté corriendo
2. Verificar webhook_url es accesible
3. Aumentar timeout en `WebhookPoster` si necesario

### Error: "Execution already active"

**Causa**: Intento de iniciar segunda ejecución en misma conversación

**Comportamiento esperado**: Se debe continuar ejecución existente, no iniciar nueva

**Verificar**:
```ruby
execution = WorkflowExecution.last
execution.status # Debe ser 'running' o 'pending'
```

## 📝 Notas

- Sistema legacy sigue funcionando en paralelo
- Migración es no-destructiva (n8n_flows no se elimina)
- Rollback es seguro (sin pérdida de datos)
- Logs tienen prefix `[N8n]` o `[Workflows]` para filtrado

## 🎉 Implementación Completa

Cuando todos los checks estén ✅:

- [ ] Marcar este documento como completado
- [ ] Agregar fecha de deployment
- [ ] Compartir resultados con equipo
- [ ] Planificar limpieza de código legacy (opcional)

---

**Última actualización**: 2026-02-19  
**Estado**: Código completo, pendiente ejecución  
**Responsable**: [Tu nombre]  
**Próxima revisión**: [Fecha después de deployment]
