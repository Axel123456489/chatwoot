# Workflow Integrations - Instrucciones de Ejecución

## Estado Actual

Todos los archivos de código han sido creados exitosamente:

### ✅ Completado
1. **Migraciones de Base de Datos** (3 archivos)
   - `20260219001420_create_workflow_integrations.rb` - Tabla principal STI
   - `20260219001421_create_workflow_executions.rb` - Historial de ejecuciones
   - `20260219001422_migrate_n8n_flows_to_workflow_executions.rb` - Migración de datos

2. **Modelos** (4 archivos)
   - `app/models/workflow_integration.rb` - Base STI abstracta
   - `app/models/workflow_execution.rb` - Gestión de ciclo de vida
   - `app/models/workflow_integrations/n8n.rb` - Implementación N8n
   - `app/models/agent_bot.rb` - Agregado `has_one :workflow_integration`

3. **Servicios** (4 archivos)
   - `app/services/workflow_integrations/webhook_poster.rb` - HTTP con reintentos
   - `app/services/workflow_integrations/trigger_detector.rb` - Detección de triggers
   - `app/services/workflow_integrations/payload_builder.rb` - Construcción de payloads
   - `app/services/workflow_integrations/executor.rb` - Orquestador principal

4. **Controllers & Listeners** (2 archivos)
   - `app/listeners/agent_bot_listener.rb` - Actualizado para usar nuevo sistema
   - `app/controllers/api/v1/integrations/workflows_controller.rb` - Nuevos endpoints API

5. **Rutas**
   - `config/routes.rb` - Agregados endpoints de workflows

### ⏳ Pendiente
- **Ejecutar migraciones** (requiere base de datos activa)

---

## Instrucciones para Continuar

### 1. Iniciar la Base de Datos

Primero, asegúrate de que PostgreSQL y Redis estén corriendo:

```bash
# Opción A: Si usas Docker Compose (con permisos adecuados)
docker-compose up -d postgres redis

# Opción B: Si tienes servicios locales
sudo service postgresql start
sudo service redis-server start

# Verificar conexión
psql -h localhost -U postgres -d chatwoot_dev -c "SELECT 1"
```

### 2. Ejecutar Migraciones

Una vez que la base de datos esté conectada:

```bash
cd /workspaces/ubuntu/chatwoot
bin/rails db:migrate
```

Esto creará:
- Tabla `workflow_integrations` (STI con type, config JSONB)
- Tabla `workflow_executions` (historial completo)
- Migrará datos de `n8n_flows` a `workflow_executions`
- Creará registros `WorkflowIntegrations::N8n` para bots existentes

### 3. Verificar Migración

```bash
# Verificar tablas creadas
bin/rails console
> WorkflowIntegration.count
> WorkflowExecution.count
> WorkflowIntegrations::N8n.count

# Ver integraciones migradas
> WorkflowIntegrations::N8n.all.each { |wi| puts "Bot: #{wi.agent_bot.name}, URL: #{wi.webhook_url}" }
```

### 4. Pruebas de Integración

Después de las migraciones, puedes probar:

#### A. Enviar mensaje en conversación con bot N8n
El sistema detectará automáticamente si debe:
- Iniciar nueva ejecución
- Reanudar conversación
- Continuar flujo activo

#### B. Usar nuevos endpoints API

```bash
# Ver ejecuciones de una conversación
curl -X GET "http://localhost:3000/api/v1/integrations/workflows/executions?conversation_id=123"

# Cancelar ejecución activa
curl -X POST "http://localhost:3000/api/v1/integrations/workflows/cancel_execution" \
  -H "Content-Type: application/json" \
  -d '{"conversation_id": 123}'

# Cambiar a otro flujo (handoff)
curl -X POST "http://localhost:3000/api/v1/integrations/workflows/switch_execution" \
  -H "Content-Type: application/json" \
  -d '{"conversation_id": 123, "execution_id": "new-flow-123"}'
```

---

## Arquitectura Implementada

### Single Table Inheritance (STI)

```
workflow_integrations (tabla)
├── type: 'WorkflowIntegrations::N8n'
├── type: 'WorkflowIntegrations::Make'     (futuro)
└── type: 'WorkflowIntegrations::Zapier'   (futuro)
```

### Flujo de Ejecución

```
1. Evento (message_created / conversation_updated)
   ↓
2. AgentBotListener detecta bot activo
   ↓
3. Si tiene WorkflowIntegration → WorkflowIntegrations::Executor
   Si no → Sistema legacy (N8nIntegration)
   ↓
4. Executor usa TriggerDetector para determinar tipo
   ↓
5. PayloadBuilder construye payload estandarizado
   ↓
6. WorkflowIntegration.start_execution() o .forward_message()
   ↓
7. WebhookPoster envía HTTP con reintentos exponenciales
   ↓
8. WorkflowExecution registra estado y actividad
```

### Ventajas del Nuevo Sistema

1. **Extensibilidad**: Agregar Make.com o Zapier es solo crear otra subclase
2. **Trazabilidad**: WorkflowExecution guarda historial completo
3. **Mantenibilidad**: Código reducido de ~700 a ~200 líneas
4. **Configuración**: JSONB config permite flags específicos por tipo
5. **Compatibilidad**: Coexiste con sistema legacy durante migración

---

## Comparación: Antes vs Después

### Antes (Legacy N8nIntegration)
- ❌ 503 líneas monolíticas
- ❌ 7+ flags booleanos dispersos
- ❌ Lógica mezclada (triggers + HTTP + estado)
- ❌ Difícil agregar nuevas plataformas
- ❌ Sin historial de ejecuciones
- ❌ Bot config sobrecargado

### Después (WorkflowIntegrations)
- ✅ ~200 líneas con separación de responsabilidades
- ✅ Config estructurado en JSONB
- ✅ Servicios reutilizables (WebhookPoster, TriggerDetector)
- ✅ STI permite múltiples plataformas
- ✅ WorkflowExecution con historial completo
- ✅ Controllers dedicados para API

---

## Limpieza Futura (Opcional)

Una vez validado el sistema nuevo (después de 2-4 semanas):

1. **Remover código legacy**:
   ```bash
   rm app/services/agent_bots/integrations/n8n_integration.rb
   rm app/models/n8n_flow.rb
   ```

2. **Crear migración para eliminar tabla vieja**:
   ```ruby
   class DropN8nFlowsTable < ActiveRecord::Migration[7.1]
     def up
       drop_table :n8n_flows
     end
   end
   ```

3. **Limpiar bot_config**:
   Remover flags `n8n_native`, `n8n_webhook_url`, etc. de AgentBot.bot_config

---

## Troubleshooting

### Error: PG::ConnectionBad
```bash
# Verificar variables de entorno
echo $POSTGRES_HOST    # debe ser 'localhost' o IP correcta
echo $POSTGRES_PORT    # debe ser '5432'

# O configurar temporalmente
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
```

### Error: WorkflowIntegration not found
```bash
# El AgentBot necesita tener workflow_integration asociado
# La migración 20260219001422 debería crearlos automáticamente
# Si no, crear manualmente:
bin/rails console
> bot = AgentBot.find(123)
> WorkflowIntegrations::N8n.create!(
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

### Rollback de migraciones
```bash
# Si algo sale mal, puedes hacer rollback
bin/rails db:rollback STEP=3

# Esto deshará:
# - Migración de datos
# - Tabla workflow_executions
# - Tabla workflow_integrations
```

---

## Próximos Pasos

1. ✅ Código completo (100%)
2. ⏳ Ejecutar migraciones cuando DB esté activa
3. ⏳ Pruebas manuales con conversaciones reales
4. ⏳ Monitorear logs para errores
5. ⏳ Ajustar configuraciones según necesidad
6. ⏳ Agregar tests automatizados (opcional)

---

## Contacto

Para cualquier problema o pregunta sobre la implementación, revisar:

1. **Logs**: `log/development.log` para ver flujo de ejecución
2. **Documentación**: 
   - `docs/N8N_INTEGRATION_ANALYSIS.md` - Análisis de problemas originales
   - `docs/WORKFLOW_INTEGRATIONS_IMPLEMENTATION_PLAN.md` - Plan detallado
3. **Código**: Todos los archivos tienen comentarios explicativos
