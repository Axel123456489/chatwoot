# Deduplicación de Storage - Guía de Uso

## Resumen del Problema

Con 300,000+ blobs, el proceso original de deduplicación tenía problemas graves de rendimiento:

- **Query inicial muy pesada**: Consulta compleja con UNION sobre todos los blobs
- **N+1 queries masivo**: Por cada checksum duplicado, hacía múltiples queries individuales
- **Sin batching**: Intentaba procesar todos los duplicados de una vez
- **Transacción gigante**: Bloqueaba la base de datos por horas

## Optimizaciones Implementadas

### 1. **Procesamiento por Batches**
- Procesa checksums en lotes de 100 (configurable)
- Reduce memoria y carga en la base de datos
- Permite interrumpir y reanudar fácilmente

### 2. **Batch Updates**
- Usa `update_all` y `delete_all` en lugar de updates individuales
- Reduce miles de queries a pocas decenas
- ~100x más rápido para grandes volúmenes

### 3. **LIMIT/OFFSET en Queries**
- La query de duplicados ahora usa paginación eficiente
- No carga todos los checksums en memoria
- Procesa de forma incremental

### 4. **Mejor Logging y Progress Tracking**
- Log por cada batch procesado
- Estadísticas en tiempo real
- Facilita debugging

## Cómo Usar

### Opción 1: Desde la UI (Super Admin)

La UI ahora procesa automáticamente en batches:

```
POST /api/v1/accounts/:account_id/storage/deduplicate
GET /api/v1/accounts/:account_id/storage/deduplication_status
```

El job se ejecuta en background con configuración optimizada automática.

### Opción 2: Rake Task (Recomendado para grandes volúmenes)

```bash
# Con límites personalizados
ACCOUNT_ID=1 bundle exec rake chatwoot:ops:deduplicate_files

# Cuando pregunte, puedes especificar:
# - Batch size: 100 (recomendado), 50 para más seguridad, 200 para más velocidad
# - Max checksums: ej. 1000 para procesar solo los primeros 1000 grupos
```

**Proceso interactivo:**
```
🔧 Deduplicando archivos...
⚠️  ADVERTENCIA: Esta operación modificará la base de datos
================================================================================
Procesando cuenta: MiCuenta (ID: 1)
Encontrados 10000+ grupos de duplicados
¿Deseas continuar? (y/n): y
Tamaño del batch (Enter = 100): 50
Máximo de checksums a procesar (Enter = todos): 2000

Iniciando deduplicación (batch_size: 50, max: 2000)...
[Storage] Processing batch 1 (50 checksum groups, offset: 0)
[Storage] Batch 1 complete: 127 total files deduplicated, 45.3 MB saved so far
...
```

### Opción 3: Desde Rails Console (Para testing)

```ruby
# Procesar en batches pequeños (ideal para testing)
account = Account.find(1)
service = AccountStorageService.new(account)

# Solo procesar 500 checksums en batches de 50
result = service.deduplicate_files(batch_size: 50, max_checksums: 500)

puts "Deduplicados: #{result[:deduplicated_count]} archivos"
puts "Espacio ahorrado: #{result[:space_saved] / 1.megabyte} MB"
puts "Checksums procesados: #{result[:processed_checksums]}"
```

### Opción 4: Job Manual de Sidekiq

```ruby
# Procesar todo en batches de 100
StorageDeduplicationJob.perform_later(account_id, batch_size: 100)

# Procesar solo 5000 checksums en batches de 200
StorageDeduplicationJob.perform_later(account_id, batch_size: 200, max_checksums: 5000)

# Ver estado
Rails.cache.read("storage_deduplication_status:#{account_id}")
```

## Estrategia Recomendada para 300,000 Blobs

Para una base de datos grande como la tuya:

### Paso 1: Test en un subset
```bash
ACCOUNT_ID=1 bundle exec rake chatwoot:ops:deduplicate_files
# Batch size: 50
# Max checksums: 100
```

Esto procesará solo 100 grupos de duplicados como prueba (~5-10 minutos).

### Paso 2: Primera pasada conservadora
```bash
ACCOUNT_ID=1 bundle exec rake chatwoot:ops:deduplicate_files
# Batch size: 100
# Max checksums: 5000
```

Procesa los primeros 5000 grupos (~30-60 minutos).

### Paso 3: Monitorear y ajustar
Revisa los logs para ver el rendimiento:
- Si va muy rápido: aumenta batch_size a 200
- Si hay errores: reduce batch_size a 50

### Paso 4: Procesar todo por chunks
```bash
# Ejecuta múltiples veces hasta completar todo
# El OFFSET automático continuará donde quedó
ACCOUNT_ID=1 bundle exec rake chatwoot:ops:deduplicate_files
# Max checksums: (dejar vacío para procesar todo)
```

## Rendimiento Esperado

Con las optimizaciones:

| Escenario | Tiempo Estimado |
|-----------|----------------|
| 100 checksums duplicados | ~2-5 minutos |
| 1,000 checksums duplicados | ~10-20 minutos |
| 10,000 checksums duplicados | ~1-2 horas |
| 50,000+ checksums duplicados | ~3-6 horas |

**Nota:** El tiempo depende de:
- Número de attachments por blob
- Complejidad de conflictos
- Carga del servidor
- Velocidad de la base de datos

## Troubleshooting

### Si el proceso es muy lento
```ruby
# Reduce el batch size
service.deduplicate_files(batch_size: 25, max_checksums: 1000)
```

### Si hay errores de memoria
```bash
# Procesa en chunks más pequeños
ACCOUNT_ID=1 bundle exec rake chatwoot:ops:deduplicate_files
# Batch size: 20
# Max checksums: 500
```

### Ver progreso en logs
```bash
tail -f log/production.log | grep -i "storage"
```

### Cancelar proceso en curso
```ruby
# Borrar el lock
Rails.cache.delete("storage_deduplication:#{account_id}")

# Ver estado
Rails.cache.read("storage_deduplication_status:#{account_id}")
```

## Seguridad

**IMPORTANTE:** Aunque el proceso ahora es muchísimo más rápido y eficiente, **siempre** debes:

1. ✅ **Hacer backup de la base de datos antes**
2. ✅ **Probar en un subset pequeño primero**  
3. ✅ **Monitorear logs durante el proceso**
4. ✅ **Ejecutar en horarios de bajo tráfico**

## Cambios Técnicos Clave

1. **`deduplicate_files`**: Ahora acepta `batch_size` y `max_checksums`
2. **`duplicate_checksums`**: Usa LIMIT/OFFSET para paginación eficiente
3. **`deduplicate_single_blob`**: Nueva función con batch updates
4. **`StorageDeduplicationJob`**: Ahora acepta parámetros de configuración
5. **Rake task**: Versión interactiva con opciones de configuración

## Migración desde Versión Anterior

Si ya comenzaste una deduplicación con la versión anterior:

1. **Detener el proceso actual** (Ctrl+C o matar el job de Sidekiq)
2. **Verificar el estado de la DB** (no debería haber corrupción)
3. **Ejecutar la nueva versión** con los parámetros recomendados

El nuevo código es **compatible hacia atrás** y puede continuar donde quedó.
