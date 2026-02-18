# frozen_string_literal: true

# Usage:
#   # Analizar almacenamiento sin cambios
#   bundle exec rake chatwoot:ops:analyze_storage
#
#   # Analizar duplicados por checksum
#   bundle exec rake chatwoot:ops:find_duplicate_files
#
#   # Limpiar archivos huérfanos (blobs sin attachments)
#   bundle exec rake chatwoot:ops:cleanup_orphan_blobs
#
#   # Deduplicar archivos (CUIDADO: modifica la base de datos)
#   bundle exec rake chatwoot:ops:deduplicate_files
#
#   # Purgar variantes de imágenes no usadas
#   bundle exec rake chatwoot:ops:purge_variants

namespace :chatwoot do
  namespace :ops do
    desc 'Analizar uso de almacenamiento de Active Storage'
    task analyze_storage: :environment do
      puts '🔍 Analizando almacenamiento de Active Storage...'
      puts '=' * 80

      total_blobs = ActiveStorage::Blob.count
      total_size = ActiveStorage::Blob.sum(:byte_size)
      total_attachments = ActiveStorage::Attachment.count

      puts "\n📊 Resumen General:"
      puts "  Total de blobs: #{total_blobs.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      puts "  Total de attachments: #{total_attachments.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      puts "  Tamaño total: #{format_bytes(total_size)}"

      # Analizar por tipo de contenido
      puts "\n📁 Por Tipo de Contenido:"
      content_types = ActiveStorage::Blob.group(:content_type).select('content_type, COUNT(*) as count, SUM(byte_size) as size')
                                         .order('size DESC').limit(20)

      content_types.each do |ct|
        puts "  #{ct.content_type || 'unknown'}: #{ct.count} archivos (#{format_bytes(ct.size)})"
      end

      # Analizar blobs huérfanos
      orphan_blobs = ActiveStorage::Blob.left_joins(:attachments)
                                        .where(active_storage_attachments: { id: nil })
      orphan_size = orphan_blobs.sum(:byte_size)

      puts "\n🗑️  Archivos Huérfanos (sin attachments):"
      puts "  Cantidad: #{orphan_blobs.count}"
      puts "  Tamaño: #{format_bytes(orphan_size)}"

      # Analizar duplicados por checksum
      duplicates = ActiveStorage::Blob.group(:checksum).having('COUNT(*) > 1')
                                      .select('checksum, COUNT(*) as count, SUM(byte_size) as total_size')
                                      .order('total_size DESC')

      duplicate_count = duplicates.sum(&:count) - duplicates.count
      duplicate_size = duplicates.sum { |d| d.total_size - (d.total_size / d.count) }

      puts "\n📋 Archivos Duplicados (mismo checksum):"
      puts "  Grupos de duplicados: #{duplicates.count}"
      puts "  Archivos duplicados: #{duplicate_count}"
      puts "  Espacio desperdiciado: #{format_bytes(duplicate_size)}"

      # Analizar variantes
      variant_count = ActiveStorage::VariantRecord.count rescue 0
      puts "\n🖼️  Variantes de Imágenes:"
      puts "  Total de variantes: #{variant_count}"

      puts "\n✨ Recomendaciones:"
      puts "  1. Ejecuta 'bundle exec rake chatwoot:ops:cleanup_orphan_blobs' para liberar #{format_bytes(orphan_size)}"
      puts "  2. Ejecuta 'bundle exec rake chatwoot:ops:deduplicate_files' para ahorrar hasta #{format_bytes(duplicate_size)}"
      puts "  3. Considera configurar un cron job para purgar archivos antiguos regularmente"
      puts '=' * 80
    end

    desc 'Encontrar archivos duplicados por checksum'
    task find_duplicate_files: :environment do
      puts '🔍 Buscando archivos duplicados...'
      puts '=' * 80

      duplicates = ActiveStorage::Blob.group(:checksum).having('COUNT(*) > 1')
                                      .select('checksum, COUNT(*) as count, SUM(byte_size) as total_size')
                                      .order('total_size DESC')
                                      .limit(50)

      duplicates.each do |dup|
        blobs = ActiveStorage::Blob.where(checksum: dup.checksum)
        first_blob = blobs.first
        wasted_space = dup.total_size - (dup.total_size / dup.count)

        puts "\n📄 Archivo: #{first_blob.filename}"
        puts "  Checksum: #{dup.checksum}"
        puts "  Tipo: #{first_blob.content_type}"
        puts "  Tamaño: #{format_bytes(first_blob.byte_size)}"
        puts "  Copias: #{dup.count}"
        puts "  Espacio desperdiciado: #{format_bytes(wasted_space)}"
        puts "  IDs: #{blobs.pluck(:id).join(', ')}"
      end

      puts '=' * 80
    end

    desc 'Limpiar blobs huérfanos (sin attachments)'
    task cleanup_orphan_blobs: :environment do
      puts '🗑️  Limpiando blobs huérfanos...'
      puts '=' * 80

      orphan_blobs = ActiveStorage::Blob.left_joins(:attachments)
                                        .where(active_storage_attachments: { id: nil })

      count = orphan_blobs.count
      size = orphan_blobs.sum(:byte_size)

      puts "Encontrados #{count} blobs huérfanos (#{format_bytes(size)})"

      if count.zero?
        puts '✨ No hay blobs huérfanos. ¡Todo limpio!'
      else
        print '¿Deseas eliminarlos? (y/n): '
        response = STDIN.gets.chomp.downcase

        if response == 'y'
          orphan_blobs.find_each do |blob|
            puts "  Eliminando #{blob.filename} (#{format_bytes(blob.byte_size)})"
            blob.purge
          end

          puts "✅ Eliminados #{count} blobs huérfanos. Liberados #{format_bytes(size)}"
        else
          puts '❌ Operación cancelada'
        end
      end

      puts '=' * 80
    end

    desc 'Deduplicar archivos con el mismo checksum'
    task deduplicate_files: :environment do
      puts '🔧 Deduplicando archivos...'
      puts '⚠️  ADVERTENCIA: Esta operación modificará la base de datos'
      puts '=' * 80

      duplicates = ActiveStorage::Blob.group(:checksum).having('COUNT(*) > 1')
                                      .select('checksum, COUNT(*) as count')

      total_duplicates = duplicates.sum(&:count) - duplicates.count

      puts "Encontrados #{duplicates.count} grupos de duplicados con #{total_duplicates} archivos duplicados"

      print '¿Deseas continuar? (y/n): '
      response = STDIN.gets.chomp.downcase

      return unless response == 'y'

      deduplicated_count = 0
      space_saved = 0

      ActiveRecord::Base.transaction do
        duplicates.each do |dup|
          blobs = ActiveStorage::Blob.where(checksum: dup.checksum).order(:created_at)
          master_blob = blobs.first
          duplicate_blobs = blobs.offset(1)

          duplicate_blobs.each do |duplicate_blob|
            # Reasignar todos los attachments del duplicado al master
            attachments = ActiveStorage::Attachment.where(blob_id: duplicate_blob.id)

            attachments.update_all(blob_id: master_blob.id)

            space_saved += duplicate_blob.byte_size
            deduplicated_count += 1

            # Purgar el blob duplicado
            duplicate_blob.purge
          end

          puts "  Deduplicado: #{master_blob.filename} (#{dup.count} copias)"
        end
      end

      puts "✅ Deduplicados #{deduplicated_count} archivos"
      puts "💾 Espacio ahorrado: #{format_bytes(space_saved)}"
      puts '=' * 80
    end

    desc 'Purgar variantes de imágenes antiguas o no usadas'
    task purge_variants: :environment do
      puts '🖼️  Purgando variantes de imágenes...'
      puts '=' * 80

      # Rails tiene un comando nativo para esto
      system('bin/rails active_storage:purge_variants')

      puts '✅ Variantes purgadas'
      puts '=' * 80
    end

    # Helper para formatear bytes en formato legible
    def format_bytes(bytes)
      return '0 B' if bytes.zero?

      units = ['B', 'KB', 'MB', 'GB', 'TB']
      exp = (Math.log(bytes) / Math.log(1024)).floor
      exp = units.length - 1 if exp >= units.length

      format('%.2f %s', bytes.to_f / (1024**exp), units[exp])
    end
  end
end
