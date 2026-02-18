# Guía de Limpieza de Almacenamiento en Chatwoot

## Problema
Los archivos en Chatwoot (especialmente en canned responses) se duplican múltiples veces cuando el mismo archivo se usa en diferentes mensajes/respuestas, causando acumulación excesiva de almacenamiento.

## Solución Implementada

### 1. Herramientas de Análisis y Limpieza

#### ✅ Paso 1: Analizar el Almacenamiento Actual

```bash
bundle exec rake chatwoot:ops:analyze_storage
```

Este comando te mostrará:
- Total de archivos y tamaño
- Desglose por tipo de contenido
- Archivos huérfanos (sin referencias)
- Archivos duplicados y espacio desperdiciado
- Recomendaciones de limpieza

#### ✅ Paso 2: Limpiar Archivos Huérfanos

```bash
bundle exec rake chatwoot:ops:cleanup_orphan_blobs
```

Elimina archivos que ya no están referenciados por ningún mensaje o respuesta predefinida. **Es seguro ejecutarlo**.

#### ✅ Paso 3: Ver Archivos Duplicados

```bash
bundle exec rake chatwoot:ops:find_duplicate_files
```

Te muestra los 50 archivos más duplicados con detalles.

#### ⚠️ Paso 4: Deduplicar Archivos (CUIDADO)

```bash
bundle exec rake chatwoot:ops:deduplicate_files
```

**IMPORTANTE**: Haz un backup de tu base de datos antes de ejecutar esto.

Este comando:
- Identifica archivos con el mismo contenido (mismo checksum)
- Mantiene una sola copia
- Redirige todas las referencias a esa copia única
- Elimina las copias duplicadas

#### ✅ Paso 5: Limpiar Variantes de Imágenes

```bash
bundle exec rake chatwoot:ops:purge_variants
```

Elimina thumbnails y variantes de imágenes que ya no se usan.

### 2. Automatización de Limpieza

#### Configurar Cron Job (Recomendado)

Edita tu crontab:
```bash
crontab -e
```

Agrega estas líneas para limpieza automática semanal:

```cron
# Limpiar archivos huérfanos cada domingo a las 2 AM
0 2 * * 0 cd /path/to/chatwoot && bundle exec rake chatwoot:ops:cleanup_orphan_blobs RAILS_ENV=production >> /var/log/chatwoot/cleanup.log 2>&1

# Purgar variantes cada domingo a las 3 AM
0 3 * * 0 cd /path/to/chatwoot && bundle exec rake chatwoot:ops:purge_variants RAILS_ENV=production >> /var/log/chatwoot/cleanup.log 2>&1
```

### 3. Prevención de Duplicados Futuros (Opcional)

El servicio `FileDeduplicationService` permite deduplicar automáticamente al subir archivos. Para implementarlo:

#### En CannedResponses:

Modifica el controlador para usar el servicio cuando se suben archivos a canned responses.

#### Ejemplo de uso en código:

```ruby
# En lugar de:
@canned_response.files.attach(params[:files])

# Usa:
params[:files].each do |file|
  FileDeduplicationService.attach_or_reuse(
    file: file,
    record: @canned_response,
    attribute: :files,
    deduplicate: true
  )
end
```

### 4. Configuración de Active Storage

#### Configurar Purga Automática

En `config/environments/production.rb`:

```ruby
# Purgar archivos desvinculados después de 2 días
config.active_storage.service_urls_expire_in = 5.minutes

# Usar variantes named para mejor control
config.active_storage.variant_processor = :vips
```

#### Limitar Tamaño de Archivos

En tus modelos (donde sea necesario):

```ruby
class CannedResponse < ApplicationRecord
  has_many_attached :files do |attachable|
    attachable.variant :thumb, resize_to_limit: [250, 250]
  end
  
  validate :files_size_validation

  private

  def files_size_validation
    files.each do |file|
      if file.byte_size > 50.megabytes
        errors.add(:files, 'debe ser menor a 50MB')
      end
    end
  end
end
```

### 5. Monitoreo Continuo

#### Script de Monitoreo

Crea un script para monitorear el crecimiento:

```bash
#!/bin/bash
# /usr/local/bin/chatwoot_storage_monitor.sh

cd /path/to/chatwoot

echo "=== Reporte de Almacenamiento Chatwoot ==="
echo "Fecha: $(date)"
echo ""

bundle exec rake chatwoot:ops:analyze_storage RAILS_ENV=production

echo ""
echo "=== Uso de Disco ==="
df -h /path/to/storage
```

### 6. Estrategia de Backup

Antes de cualquier operación de limpieza masiva:

```bash
# Backup de base de datos
docker exec chatwoot_postgres pg_dump -U postgres chatwoot_production > backup_$(date +%Y%m%d).sql

# Backup de archivos (si usas almacenamiento local)
tar -czf storage_backup_$(date +%Y%m%d).tar.gz storage/
```

### 7. Alternativas de Almacenamiento

Si el almacenamiento local sigue siendo un problema, considera migrar a:

#### AWS S3
```ruby
# config/storage.yml
amazon:
  service: S3
  access_key_id: <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region: us-east-1
  bucket: your-bucket-name
```

#### Cloudflare R2 (compatible con S3, más barato)
```ruby
# config/storage.yml
cloudflare:
  service: S3
  access_key_id: <%= ENV['R2_ACCESS_KEY_ID'] %>
  secret_access_key: <%= ENV['R2_SECRET_ACCESS_KEY'] %>
  region: auto
  bucket: your-bucket-name
  endpoint: https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
```

#### MinIO (S3-compatible, self-hosted)
```ruby
# config/storage.yml
minio:
  service: S3
  access_key_id: <%= ENV['MINIO_ACCESS_KEY'] %>
  secret_access_key: <%= ENV['MINIO_SECRET_KEY'] %>
  region: us-east-1
  bucket: chatwoot
  endpoint: https://minio.yourdomain.com
  force_path_style: true
```

Cambia en `config/environments/production.rb`:
```ruby
config.active_storage.service = :amazon # o :cloudflare, :minio
```

## Resultados Esperados

Después de ejecutar la limpieza completa, deberías ver:

- ✅ **30-70% de reducción** en almacenamiento dependiendo de la cantidad de duplicados
- ✅ **Eliminación de archivos huérfanos** que ya no sirven
- ✅ **Optimización de variantes** de imágenes
- ✅ **Base de datos más limpia** con referencias correctas

## Preguntas Frecuentes

### ¿Es seguro ejecutar deduplicate_files?
Sí, pero **haz un backup primero**. El proceso mantiene una copia del archivo y solo actualiza las referencias.

### ¿Afectará el rendimiento?
No. Las operaciones solo actualizan referencias en la base de datos. Los archivos siguen siendo accesibles.

### ¿Con qué frecuencia debo ejecutar la limpieza?
- **Archivos huérfanos**: Semanalmente (automatizado con cron)
- **Deduplicación**: Mensualmente o cuando notes alto uso de almacenamiento
- **Variantes**: Mensualmente

### ¿Puedo revertir la deduplicación?
No fácilmente. Por eso es crucial hacer un backup antes.

## Soporte

Si tienes problemas, revisa los logs:
```bash
tail -f log/production.log
```

Para más ayuda, consulta la documentación de Active Storage:
https://edgeguides.rubyonrails.org/active_storage_overview.html
