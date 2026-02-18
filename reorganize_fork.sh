#!/bin/bash
# Script para reorganizar el fork de forma segura
# Opción B: Fork Limpio con cherry-pick

set -e  # Salir si hay error

cd /workspaces/ubuntu/chatwoot

echo "=========================================="
echo "  REORGANIZACIÓN DEL FORK DE CHATWOOT"
echo "=========================================="
echo ""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para confirmar acción
confirm() {
    read -p "$(echo -e ${YELLOW}"$1 (y/n): "${NC})" -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Paso 1: Crear backup
echo -e "${BLUE}📦 PASO 1: Creando backup completo...${NC}"
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$HOME/chatwoot-backup-$BACKUP_DATE.bundle"

if confirm "¿Crear backup completo en bundle?"; then
    git bundle create "$BACKUP_FILE" --all
    echo -e "${GREEN}✅ Backup creado: $BACKUP_FILE${NC}"
    
    # Verificar el bundle
    if git bundle verify "$BACKUP_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Backup verificado correctamente${NC}"
    else
        echo -e "${RED}❌ Error: El backup no es válido${NC}"
        exit 1
    fi
else
    echo -e "${RED}⚠️  Backup cancelado. No es seguro continuar sin backup.${NC}"
    exit 1
fi
echo ""

# Paso 2: Crear rama de respaldo
echo -e "${BLUE}📋 PASO 2: Creando rama de respaldo...${NC}"
BACKUP_BRANCH="backup-develop-$BACKUP_DATE"
git branch "$BACKUP_BRANCH"
echo -e "${GREEN}✅ Rama de respaldo creada: $BACKUP_BRANCH${NC}"

if confirm "¿Hacer push de la rama de respaldo al origen?"; then
    git push origin "$BACKUP_BRANCH"
    echo -e "${GREEN}✅ Rama de respaldo enviada a GitHub${NC}"
fi
echo ""

# Paso 3: Verificar upstream
echo -e "${BLUE}🔍 PASO 3: Verificando configuración de upstream...${NC}"
if git remote | grep -q "^upstream$"; then
    echo -e "${GREEN}✅ Upstream configurado correctamente${NC}"
    git fetch upstream
    echo -e "${GREEN}✅ Upstream actualizado${NC}"
else
    echo -e "${YELLOW}⚠️  Upstream no configurado${NC}"
    if confirm "¿Configurar upstream a chatwoot/chatwoot?"; then
        git remote add upstream https://github.com/chatwoot/chatwoot.git
        git fetch upstream
        echo -e "${GREEN}✅ Upstream configurado y actualizado${NC}"
    fi
fi
echo ""

# Paso 4: Encontrar commit base
echo -e "${BLUE}📌 PASO 4: Identificando punto base...${NC}"
BASE_COMMIT=$(git merge-base develop upstream/develop)
echo -e "${GREEN}Commit base: $BASE_COMMIT${NC}"
BASE_MESSAGE=$(git log --oneline -1 $BASE_COMMIT)
echo -e "Mensaje: $BASE_MESSAGE"
echo ""

# Paso 5: Crear nueva rama limpia
echo -e "${BLUE}🌿 PASO 5: Creando nueva rama limpia...${NC}"
CLEAN_BRANCH="develop-clean-$BACKUP_DATE"

if git rev-parse --verify "$CLEAN_BRANCH" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  La rama $CLEAN_BRANCH ya existe${NC}"
    if confirm "¿Eliminar y recrear?"; then
        git branch -D "$CLEAN_BRANCH"
    else
        echo -e "${RED}❌ Cancelado${NC}"
        exit 1
    fi
fi

git checkout -b "$CLEAN_BRANCH" upstream/develop
echo -e "${GREEN}✅ Rama limpia creada: $CLEAN_BRANCH${NC}"
echo -e "${GREEN}✅ Basada en: upstream/develop (última versión)${NC}"
echo ""

# Paso 6: Preparar commits organizados
echo -e "${BLUE}📝 PASO 6: Preparando commits organizados por funcionalidad...${NC}"
echo ""
echo "A continuación vamos a crear commits organizados para cada funcionalidad."
echo "Puedes elegir cuáles funcionalidades incluir."
echo ""

# Lista de funcionalidades a reorganizar
declare -A FEATURES
FEATURES=(
    ["storage"]="Storage Management System"
    ["waha"]="WAHA WhatsApp Integration"
    ["calls"]="WhatsApp P2P Calls System"
    ["canned"]="Canned Responses with Attachments"
    ["n8n"]="N8N Workflow Integration"
    ["templates"]="WhatsApp Templates & Reactions"
    ["performance"]="Performance Optimizations"
    ["dashboard"]="Dashboard & UI Improvements"
)

declare -a SELECTED_FEATURES

echo "Funcionalidades disponibles:"
echo ""
for key in "${!FEATURES[@]}"; do
    echo "  [$key] - ${FEATURES[$key]}"
done
echo ""

# Función para crear commit de una funcionalidad
create_feature_commit() {
    local feature_key=$1
    local feature_name=$2
    local pattern=$3
    
    echo -e "${BLUE}🔨 Procesando: $feature_name${NC}"
    
    # Obtener archivos relevantes
    git checkout develop
    FILES=$(git diff $BASE_COMMIT HEAD --name-only | grep -iE "$pattern" || true)
    
    if [ -z "$FILES" ]; then
        echo -e "${YELLOW}⚠️  No se encontraron archivos para $feature_name${NC}"
        return
    fi
    
    git checkout "$CLEAN_BRANCH"
    
    # Aplicar cambios de esos archivos específicos
    echo "$FILES" | while read file; do
        if [ ! -z "$file" ] && [ -f "$file" ]; then
            git checkout develop -- "$file" 2>/dev/null || echo "  ⚠️  No se pudo copiar: $file"
        fi
    done
    
    # Verificar si hay cambios para commitear
    if git diff --cached --quiet && git diff --quiet; then
        echo -e "${YELLOW}⚠️  No hay cambios para commitear en $feature_name${NC}"
        return
    fi
    
    git add -A
    
    return 0
}

# Menú interactivo
echo "=========================================="
echo "  SELECCIÓN DE FUNCIONALIDADES"
echo "=========================================="
echo ""
echo "¿Qué deseas hacer?"
echo ""
echo "  1) Reorganizar todas las funcionalidades automáticamente"
echo "  2) Seleccionar funcionalidades manualmente"
echo "  3) Salir y hacer manual"
echo ""
read -p "Opción (1-3): " OPTION

case $OPTION in
    1)
        echo -e "${GREEN}✅ Reorganizando todas las funcionalidades...${NC}"
        echo ""
        
        # Storage Management
        if confirm "¿Incluir Storage Management?"; then
            echo -e "${BLUE}Creating: Storage Management${NC}"
            git checkout develop
            git diff $BASE_COMMIT HEAD --name-only | grep -iE "storage" | xargs git checkout develop -- 2>/dev/null || true
            git checkout "$CLEAN_BRANCH"
            git checkout develop -- $(git diff $BASE_COMMIT HEAD --name-only | grep -iE "storage") 2>/dev/null || true
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "feat(storage): Add complete storage management system

- Add storage control UI with disk usage indicators and cleanup tools
- Implement AccountStorageService for automatic file cleanup
- Add i18n translations (EN, ES) for storage management
- Fix Lucide icon rendering in storage views
- Add API endpoints for storage monitoring and cleanup operations
- Add database migrations for storage analysis indexes
- Include comprehensive specs and documentation"
                echo -e "${GREEN}✅ Commit creado para Storage Management${NC}"
            fi
        fi
        
        # WAHA Integration
        if confirm "¿Incluir WAHA Integration?"; then
            echo -e "${BLUE}Creating: WAHA Integration${NC}"
            git checkout develop
            git checkout "$CLEAN_BRANCH"
            git checkout develop -- $(git diff $BASE_COMMIT HEAD --name-only | grep -iE "waha") 2>/dev/null || true
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "feat(waha): Add complete WAHA WhatsApp integration

- Implement WAHA channel adapter with advanced configuration
- Add modern UI with auto-refresh QR code functionality
- Support for multiple WAHA instances per account
- Add webhook handling for WAHA events
- Include session management and status sync
- Add comprehensive error handling and logging"
                echo -e "${GREEN}✅ Commit creado para WAHA Integration${NC}"
            fi
        fi
        
        # WhatsApp Calls
        if confirm "¿Incluir WhatsApp P2P Calls?"; then
            echo -e "${BLUE}Creating: WhatsApp P2P Calls${NC}"
            git checkout develop
            git checkout "$CLEAN_BRANCH"
            git checkout develop -- $(git diff $BASE_COMMIT HEAD --name-only | grep -iE "(whatsapp.*(call|p2p))|(call.*whatsapp)") 2>/dev/null || true
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "feat(whatsapp-calls): Implement P2P WhatsApp calling system

- Add core P2P calling functionality for WhatsApp channels
- Implement signaling and ICE candidate exchange via WebRTC
- Add call detection and hangup handling
- Support for inbound and outbound calls with proper routing
- Add call history, analytics, and recording playback
- Include comprehensive UI components for call management
- Add ActionCable integration for real-time call events
- Include permission management and error handling"
                echo -e "${GREEN}✅ Commit creado para WhatsApp Calls${NC}"
            fi
        fi
        
        # Canned Responses
        if confirm "¿Incluir Canned Responses with Attachments?"; then
            echo -e "${BLUE}Creating: Canned Responses${NC}"
            git checkout develop
            git checkout "$CLEAN_BRANCH"
            git checkout develop -- $(git diff $BASE_COMMIT HEAD --name-only | grep -iE "canned") 2>/dev/null || true
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "feat(canned-responses): Add attachment support to canned responses

- Enable file attachments in canned responses
- Improve text insertion flow in rich text editor
- Add attachment preview and management UI
- Support multiple file types (images, documents, etc.)
- Fix editor integration issues"
                echo -e "${GREEN}✅ Commit creado para Canned Responses${NC}"
            fi
        fi
        
        # N8N Integration
        if confirm "¿Incluir N8N Integration?"; then
            echo -e "${BLUE}Creating: N8N Integration${NC}"
            git checkout develop
            git checkout "$CLEAN_BRANCH"
            git checkout develop -- $(git diff $BASE_COMMIT HEAD --name-only | grep -iE "n8n") 2>/dev/null || true
            git add -A
            if ! git diff --cached --quiet; then
                git commit -m "feat(n8n): Add complete N8N workflow integration

- Implement N8N webhook integration system
- Add automation triggers for conversations and messages
- Support for bidirectional data flow
- Add configuration UI for N8N endpoints
- Include authentication and security features"
                echo -e "${GREEN}✅ Commit creado para N8N Integration${NC}"
            fi
        fi
        
        echo -e "${GREEN}✅ Reorganización completada${NC}"
        ;;
    2)
        echo -e "${YELLOW}Modo manual seleccionado${NC}"
        echo "Por favor, continúa manualmente siguiendo la guía en FORK_CLEANUP_GUIDE.md"
        ;;
    3)
        echo -e "${YELLOW}Saliendo...${NC}"
        echo "Puedes continuar manualmente con la rama: $CLEAN_BRANCH"
        exit 0
        ;;
    *)
        echo -e "${RED}Opción inválida${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "  SIGUIENTE PASOS"
echo "=========================================="
echo ""
echo "Tu nueva rama limpia: ${GREEN}$CLEAN_BRANCH${NC}"
echo "Tu rama de respaldo: ${GREEN}$BACKUP_BRANCH${NC}"
echo "Tu backup bundle: ${GREEN}$BACKUP_FILE${NC}"
echo ""
echo "Ahora puedes:"
echo ""
echo "1. Revisar los commits en la rama limpia:"
echo "   ${BLUE}git log $CLEAN_BRANCH --oneline${NC}"
echo ""
echo "2. Probar que todo funciona correctamente"
echo ""
echo "3. Si todo está bien, reemplazar develop:"
echo "   ${BLUE}git checkout develop${NC}"
echo "   ${BLUE}git reset --hard $CLEAN_BRANCH${NC}"
echo "   ${BLUE}git push -f origin develop${NC}"
echo ""
echo "4. O mantener ambas ramas y fusionar:"
echo "   ${BLUE}git checkout develop${NC}"
echo "   ${BLUE}git reset --hard $CLEAN_BRANCH${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANTE: Force push reescribe la historia del repositorio${NC}"
echo -e "${YELLOW}⚠️  Asegúrate de que nadie más esté trabajando en tu fork${NC}"
echo ""
echo -e "${GREEN}✅ Script completado exitosamente${NC}"
