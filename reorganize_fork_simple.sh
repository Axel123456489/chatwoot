#!/bin/bash
# Script simplificado para reorganizar el fork - Método de Patches
# Este método es más seguro y más fácil de controlar

set -e

cd /workspaces/ubuntu/chatwoot

echo "=========================================="
echo "  REORGANIZACIÓN LIMPIA DEL FORK"
echo "=========================================="
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Fecha para nombres únicos
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)

echo -e "${BLUE}Este script te ayudará a reorganizar tu fork de manera segura${NC}"
echo ""
echo "Pasos que realizaremos:"
echo "  1. Crear backup completo"
echo "  2. Encontrar el punto base (último commit de upstream)"
echo "  3. Extraer patches organizados por funcionalidad"
echo "  4. Crear nueva rama limpia desde upstream"
echo "  5. Aplicar patches de forma organizada"
echo ""

read -p "¿Continuar? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelado"
    exit 0
fi

# PASO 1: Backup
echo ""
echo -e "${BLUE}📦 PASO 1: Creando backup...${NC}"
BACKUP_FILE="$HOME/chatwoot-backup-$BACKUP_DATE.bundle"
git bundle create "$BACKUP_FILE" --all
git bundle verify "$BACKUP_FILE" > /dev/null && echo -e "${GREEN}✅ Backup creado y verificado: $BACKUP_FILE${NC}"

# Backup de rama actual también
BACKUP_BRANCH="backup-develop-$BACKUP_DATE"
git branch "$BACKUP_BRANCH"
echo -e "${GREEN}✅ Rama de respaldo creada: $BACKUP_BRANCH${NC}"

# PASO 2: Actualizar upstream
echo ""
echo -e "${BLUE}🔄 PASO 2: Actualizando upstream...${NC}"
if ! git remote | grep -q "^upstream$"; then
    git remote add upstream https://github.com/chatwoot/chatwoot.git
fi
git fetch upstream
echo -e "${GREEN}✅ Upstream actualizado${NC}"

# PASO 3: Encontrar punto base
echo ""
echo -e "${BLUE}📌 PASO 3: Encontrando punto base...${NC}"
BASE_COMMIT=$(git merge-base develop upstream/develop)
echo -e "${GREEN}Commit base: $BASE_COMMIT${NC}"
git log --oneline -1 $BASE_COMMIT

# PASO 4: Crear directorio de patches
echo ""
echo -e "${BLUE}📝 PASO 4: Creando patches organizados...${NC}"
PATCHES_DIR="$HOME/chatwoot-patches-$BACKUP_DATE"
mkdir -p "$PATCHES_DIR"
echo -e "${GREEN}✅ Directorio de patches: $PATCHES_DIR${NC}"

# Verificar qué archivos fueron modificados
echo ""
echo "Analizando cambios..."
TOTAL_FILES=$(git diff $BASE_COMMIT develop --name-only | wc -l)
echo "Total de archivos modificados: $TOTAL_FILES"
echo ""

# Función para crear patch
create_patch() {
    local feature_name=$1
    local file_pattern=$2
    local patch_file="$PATCHES_DIR/${feature_name}.patch"
    
    echo -e "${BLUE}Creando patch para: $feature_name${NC}"
    
    # Obtener lista de archivos que coinciden con el patrón
    local files=$(git diff $BASE_COMMIT develop --name-only | grep -iE "$file_pattern" || true)
    
    if [ -z "$files" ]; then
        echo -e "${YELLOW}⚠️  No hay archivos para $feature_name${NC}"
        return 1
    fi
    
    local count=$(echo "$files" | wc -l)
    echo "  Archivos encontrados: $count"
    
    # Crear el patch
    git diff $BASE_COMMIT develop -- $files > "$patch_file"
    
    if [ -s "$patch_file" ]; then
        local size=$(wc -c < "$patch_file")
        echo -e "${GREEN}  ✅ Patch creado: $(basename $patch_file) (${size} bytes)${NC}"
        echo "  Vista previa de archivos:"
        echo "$files" | head -5 | sed 's/^/    - /'
        if [ $count -gt 5 ]; then
            echo "    ... y $((count - 5)) más"
        fi
        return 0
    else
        echo -e "${YELLOW}  ⚠️  Patch vacío, eliminando${NC}"
        rm "$patch_file"
        return 1
    fi
}

# Crear patches por funcionalidad
echo ""
echo "Creando patches individuales por funcionalidad..."
echo ""

create_patch "01-storage-management" "storage"
create_patch "02-waha-integration" "waha"
create_patch "03-whatsapp-calls" "(whatsapp.*(call|p2p|calling))|(call.*whatsapp)"
create_patch "04-canned-responses" "canned"
create_patch "05-n8n-integration" "n8n"
create_patch "06-templates-reactions" "(template|reaction)"

# Patches para archivos de configuración, docs, etc
echo ""
echo -e "${BLUE}Creando patches adicionales...${NC}"
git diff $BASE_COMMIT develop -- config/ > "$PATCHES_DIR/10-config-changes.patch" 2>/dev/null || true
git diff $BASE_COMMIT develop -- docs/ *.md > "$PATCHES_DIR/11-documentation.patch" 2>/dev/null || true
git diff $BASE_COMMIT develop -- spec/ > "$PATCHES_DIR/12-tests.patch" 2>/dev/null || true

# Crear patch con todo lo demás
echo ""
echo -e "${BLUE}Creando patch con cambios restantes...${NC}"
git diff $BASE_COMMIT develop > "$PATCHES_DIR/99-all-changes.patch"

# Mostrar resumen de patches
echo ""
echo -e "${GREEN}✅ Patches creados:${NC}"
ls -lh "$PATCHES_DIR"/*.patch | awk '{printf "  %s (%s)\n", $9, $5}'

echo ""
echo -e "${BLUE}📊 Siguiente paso: Crear rama limpia y aplicar patches${NC}"
echo ""

read -p "¿Crear nueva rama limpia ahora? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${YELLOW}OK, puedes continuar manualmente más tarde${NC}"
    echo ""
    echo "Tus patches están en: $PATCHES_DIR"
    echo "Tu backup bundle está en: $BACKUP_FILE"
    echo "Tu rama de respaldo: $BACKUP_BRANCH"
    exit 0
fi

# PASO 5: Crear rama limpia
echo ""
echo -e "${BLUE}🌿 PASO 5: Creando rama limpia desde upstream/develop...${NC}"
CLEAN_BRANCH="develop-clean"

if git rev-parse --verify "$CLEAN_BRANCH" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  La rama $CLEAN_BRANCH ya existe${NC}"
    read -p "¿Eliminar y recrear? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git branch -D "$CLEAN_BRANCH"
    else
        CLEAN_BRANCH="develop-clean-$BACKUP_DATE"
        echo "Usando nombre alternativo: $CLEAN_BRANCH"
    fi
fi

git checkout -b "$CLEAN_BRANCH" upstream/develop
echo -e "${GREEN}✅ Rama limpia creada: $CLEAN_BRANCH${NC}"
echo -e "${GREEN}✅ Basada en la última versión de upstream/develop${NC}"

# PASO 6: Guía para aplicar patches
echo ""
echo "=========================================="
echo "  APLICACIÓN DE PATCHES"
echo "=========================================="
echo ""
echo "Ahora puedes aplicar los patches uno por uno y crear commits organizados."
echo ""
echo "Para cada funcionalidad, ejecuta:"
echo ""
echo -e "${BLUE}# 1. Storage Management${NC}"
echo "git apply $PATCHES_DIR/01-storage-management.patch"
echo "git add -A"
echo 'git commit -m "feat(storage): Add complete storage management system

- Add storage control UI with disk usage indicators
- Implement AccountStorageService for automatic cleanup
- Add i18n translations and comprehensive specs
- Include documentation and rake tasks"'
echo ""

echo -e "${BLUE}# 2. WAHA Integration${NC}"
echo "git apply $PATCHES_DIR/02-waha-integration.patch"
echo "git add -A"
echo 'git commit -m "feat(waha): Add complete WAHA WhatsApp integration

- Implement WAHA channel adapter with advanced configuration
- Add modern UI with auto-refresh QR code
- Support multiple WAHA instances per account
- Include session management and status sync"'
echo ""

echo -e "${BLUE}# 3. WhatsApp Calls${NC}"
echo "git apply $PATCHES_DIR/03-whatsapp-calls.patch"
echo "git add -A"
echo 'git commit -m "feat(whatsapp-calls): Implement P2P calling system

- Add core P2P calling functionality with WebRTC
- Implement signaling and ICE candidate exchange
- Support inbound/outbound calls with proper routing
- Add call history, analytics, and recording playback
- Include comprehensive UI and error handling"'
echo ""

echo -e "${BLUE}# 4. Canned Responses${NC}"
echo "git apply $PATCHES_DIR/04-canned-responses.patch"
echo "git add -A"
echo 'git commit -m "feat(canned-responses): Add attachment support

- Enable file attachments in canned responses
- Improve text insertion in rich text editor
- Add attachment preview and management UI"'
echo ""

echo -e "${BLUE}# 5. N8N Integration${NC}"
echo "git apply $PATCHES_DIR/05-n8n-integration.patch"
echo "git add -A"
echo 'git commit -m "feat(n8n): Add N8N workflow integration

- Implement N8N webhook integration system
- Add automation triggers for conversations
- Support bidirectional data flow
- Include configuration UI and security features"'
echo ""

echo ""
echo -e "${GREEN}=========================================="
echo "  RESUMEN"
echo "==========================================${NC}"
echo ""
echo "✅ Backup bundle: $BACKUP_FILE"
echo "✅ Backup branch: $BACKUP_BRANCH"
echo "✅ Patches directory: $PATCHES_DIR"
echo "✅ Clean branch: $CLEAN_BRANCH"
echo ""
echo "Estás ahora en la rama: $(git branch --show-current)"
echo ""
echo -e "${YELLOW}Próximos pasos:${NC}"
echo "1. Aplica los patches uno por uno siguiendo las instrucciones arriba"
echo "2. Prueba que todo funciona"
echo "3. Cuando estés satisfecho, reemplaza develop:"
echo "   ${BLUE}git checkout develop${NC}"
echo "   ${BLUE}git reset --hard $CLEAN_BRANCH${NC}"
echo "   ${BLUE}git push -f origin develop${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANTE: Force push reescribe la historia${NC}"
echo ""
