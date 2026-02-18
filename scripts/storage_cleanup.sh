#!/bin/bash

# Script de Análisis y Limpieza Rápida de Almacenamiento Chatwoot
# Uso: ./scripts/storage_cleanup.sh [analyze|clean|deduplicate|full]

set -e

CHATWOOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CHATWOOT_DIR"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Chatwoot Storage Cleanup & Optimization Tool        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if Rails environment is set
if [ -z "$RAILS_ENV" ]; then
    RAILS_ENV="production"
    echo -e "${YELLOW}⚠️  RAILS_ENV no definido, usando: production${NC}"
fi

echo -e "${BLUE}Entorno: ${RAILS_ENV}${NC}\n"

# Function to show help
show_help() {
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos disponibles:"
    echo "  analyze      - Analizar uso de almacenamiento (solo lectura)"
    echo "  clean        - Limpiar archivos huérfanos (seguro)"
    echo "  deduplicate  - Deduplicar archivos duplicados (requiere backup)"
    echo "  full         - Análisis + limpieza + deduplicación (requiere backup)"
    echo "  help         - Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0 analyze"
    echo "  $0 clean"
    echo "  RAILS_ENV=production $0 deduplicate"
}

# Function to analyze storage
analyze_storage() {
    echo -e "${GREEN}📊 Analizando almacenamiento...${NC}\n"
    bundle exec rake chatwoot:ops:analyze_storage RAILS_ENV=$RAILS_ENV
}

# Function to clean orphan blobs
clean_orphans() {
    echo -e "${GREEN}🗑️  Limpiando archivos huérfanos...${NC}\n"
    bundle exec rake chatwoot:ops:cleanup_orphan_blobs RAILS_ENV=$RAILS_ENV
}

# Function to deduplicate files
deduplicate_files() {
    echo -e "${RED}⚠️  ADVERTENCIA: La deduplicación modificará la base de datos${NC}"
    echo -e "${YELLOW}Se recomienda hacer un backup antes de continuar${NC}\n"
    
    read -p "¿Has hecho un backup de tu base de datos? (s/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${RED}❌ Abortado. Haz un backup primero.${NC}"
        echo ""
        echo "Comandos de backup:"
        echo "  # PostgreSQL"
        echo "  pg_dump -U postgres -d chatwoot_${RAILS_ENV} > backup_\$(date +%Y%m%d).sql"
        echo ""
        echo "  # Docker"
        echo "  docker exec chatwoot_postgres pg_dump -U postgres chatwoot_${RAILS_ENV} > backup_\$(date +%Y%m%d).sql"
        exit 1
    fi
    
    echo -e "\n${GREEN}🔧 Deduplicando archivos...${NC}\n"
    bundle exec rake chatwoot:ops:deduplicate_files RAILS_ENV=$RAILS_ENV
}

# Function to purge variants
purge_variants() {
    echo -e "${GREEN}🖼️  Purgando variantes de imágenes...${NC}\n"
    bundle exec rake chatwoot:ops:purge_variants RAILS_ENV=$RAILS_ENV
}

# Function to run full cleanup
full_cleanup() {
    echo -e "${BLUE}🚀 Ejecutando limpieza completa...${NC}\n"
    
    analyze_storage
    echo -e "\n${BLUE}════════════════════════════════════════════════════${NC}\n"
    
    clean_orphans
    echo -e "\n${BLUE}════════════════════════════════════════════════════${NC}\n"
    
    purge_variants
    echo -e "\n${BLUE}════════════════════════════════════════════════════${NC}\n"
    
    deduplicate_files
    echo -e "\n${BLUE}════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${GREEN}✨ Análisis post-limpieza:${NC}\n"
    analyze_storage
}

# Main script logic
case "${1:-help}" in
    analyze)
        analyze_storage
        ;;
    clean)
        clean_orphans
        purge_variants
        ;;
    deduplicate)
        deduplicate_files
        ;;
    full)
        full_cleanup
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}❌ Comando desconocido: $1${NC}\n"
        show_help
        exit 1
        ;;
esac

echo -e "\n${GREEN}✅ Completado!${NC}"
