#!/bin/bash
# Script de inicio rápido - Te ayuda a decidir qué hacer

cd /workspaces/ubuntu/chatwoot

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear

echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║                                                        ║"
echo "║     🧹 LIMPIEZA DE FORK DE CHATWOOT 🧹                ║"
echo "║                                                        ║"
echo "║        Reorganiza tus commits de forma segura         ║"
echo "║                                                        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Verificar que estamos en un repo git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: No estás en un repositorio Git${NC}"
    exit 1
fi

# Mostrar situación actual
echo -e "${BOLD}📊 TU SITUACIÓN ACTUAL:${NC}"
echo ""

# Contar commits del usuario
COMMITS_COUNT=$(git log --author="Axel123456489" --oneline --all | wc -l)
echo -e "  📝 Commits de Axel123456489: ${YELLOW}${COMMITS_COUNT}${NC}"

# Branch actual
CURRENT_BRANCH=$(git branch --show-current)
echo -e "  🌿 Rama actual: ${GREEN}${CURRENT_BRANCH}${NC}"

# Estado del working tree
if git diff --quiet && git diff --cached --quiet; then
    echo -e "  ✅ Working tree: ${GREEN}Limpio${NC}"
else
    echo -e "  ⚠️  Working tree: ${YELLOW}Hay cambios sin commitear${NC}"
fi

# Verificar si upstream está configurado
if git remote | grep -q "^upstream$"; then
    echo -e "  ✅ Upstream: ${GREEN}Configurado${NC}"
    UPSTREAM_STATUS="OK"
else
    echo -e "  ⚠️  Upstream: ${YELLOW}No configurado${NC}"
    UPSTREAM_STATUS="MISSING"
fi

# Analizar cambios
echo ""
echo -e "${BLUE}🔍 Analizando tus cambios...${NC}"
if [ "$UPSTREAM_STATUS" = "OK" ]; then
    BASE_COMMIT=$(git merge-base develop upstream/develop 2>/dev/null || echo "")
    if [ ! -z "$BASE_COMMIT" ]; then
        FILES_CHANGED=$(git diff $BASE_COMMIT HEAD --name-only 2>/dev/null | wc -l)
        LINES_ADDED=$(git diff $BASE_COMMIT HEAD --shortstat 2>/dev/null | grep -oP '\d+(?= insertion)' || echo "0")
        LINES_DELETED=$(git diff $BASE_COMMIT HEAD --shortstat 2>/dev/null | grep -oP '\d+(?= deletion)' || echo "0")
        
        echo -e "  📁 Archivos modificados: ${YELLOW}${FILES_CHANGED}${NC}"
        echo -e "  ➕ Líneas agregadas: ${GREEN}${LINES_ADDED}${NC}"
        echo -e "  ➖ Líneas eliminadas: ${RED}${LINES_DELETED}${NC}"
    fi
fi

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
echo ""

# Menú de opciones
echo -e "${BOLD}¿Qué quieres hacer?${NC}"
echo ""
echo -e "  ${BOLD}1)${NC} ${GREEN}🚀 Reorganizar mi fork AHORA${NC} ${CYAN}(Recomendado)${NC}"
echo "     Ejecuta el script automatizado que hace todo por ti"
echo ""
echo -e "  ${BOLD}2)${NC} ${BLUE}📊 Ver análisis detallado de mis cambios${NC}"
echo "     Muestra qué archivos modificaste por funcionalidad"
echo ""
echo -e "  ${BOLD}3)${NC} ${YELLOW}📖 Abrir guía paso a paso${NC}"
echo "     Lee la documentación completa antes de comenzar"
echo ""
echo -e "  ${BOLD}4)${NC} ${YELLOW}🔧 Solo crear backup (sin reorganizar)${NC}"
echo "     Crea un backup de seguridad sin hacer cambios"
echo ""
echo -e "  ${BOLD}5)${NC} ℹ️  Ver archivos de ayuda disponibles"
echo ""
echo -e "  ${BOLD}0)${NC} ❌ Salir"
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"
echo ""

read -p "$(echo -e ${CYAN}"Selecciona una opción (0-5): "${NC})" OPTION

case $OPTION in
    1)
        echo ""
        echo -e "${GREEN}🚀 Iniciando reorganización automatizada...${NC}"
        echo ""
        sleep 1
        
        if [ ! -f "./reorganize_fork_simple.sh" ]; then
            echo -e "${RED}❌ Error: No se encuentra reorganize_fork_simple.sh${NC}"
            exit 1
        fi
        
        exec ./reorganize_fork_simple.sh
        ;;
        
    2)
        echo ""
        echo -e "${BLUE}📊 Ejecutando análisis detallado...${NC}"
        echo ""
        sleep 1
        
        if [ ! -f "./analyze_changes.sh" ]; then
            echo -e "${RED}❌ Error: No se encuentra analyze_changes.sh${NC}"
            exit 1
        fi
        
        ./analyze_changes.sh | less -R
        ;;
        
    3)
        echo ""
        echo -e "${YELLOW}📖 Abriendo guía...${NC}"
        echo ""
        
        if [ -f "QUICK_START_CLEANUP.md" ]; then
            echo "Guía disponible en: QUICK_START_CLEANUP.md"
            echo ""
            echo "Opciones para leerla:"
            echo "  1. cat QUICK_START_CLEANUP.md | less"
            echo "  2. code QUICK_START_CLEANUP.md (en VS Code)"
            echo "  3. Abrir el archivo en tu editor preferido"
            echo ""
            read -p "¿Abrir en less? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                less QUICK_START_CLEANUP.md
            fi
        else
            echo -e "${RED}❌ No se encuentra QUICK_START_CLEANUP.md${NC}"
        fi
        ;;
        
    4)
        echo ""
        echo -e "${YELLOW}🔧 Creando backup de seguridad...${NC}"
        echo ""
        
        BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
        BACKUP_FILE="$HOME/chatwoot-backup-$BACKUP_DATE.bundle"
        BACKUP_BRANCH="backup-develop-$BACKUP_DATE"
        
        echo "Creando bundle..."
        git bundle create "$BACKUP_FILE" --all
        
        if git bundle verify "$BACKUP_FILE" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Bundle creado y verificado${NC}"
            echo "   Ubicación: $BACKUP_FILE"
            
            SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
            echo "   Tamaño: $SIZE"
        else
            echo -e "${RED}❌ Error al crear bundle${NC}"
            exit 1
        fi
        
        echo ""
        echo "Creando rama de respaldo..."
        git branch "$BACKUP_BRANCH"
        echo -e "${GREEN}✅ Rama creada: $BACKUP_BRANCH${NC}"
        
        echo ""
        read -p "¿Hacer push de la rama de respaldo a GitHub? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git push origin "$BACKUP_BRANCH"
            echo -e "${GREEN}✅ Backup enviado a GitHub${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}✅ Backup completado${NC}"
        echo ""
        echo "Puedes restaurar usando:"
        echo "  git clone $BACKUP_FILE chatwoot-restored"
        ;;
        
    5)
        echo ""
        echo -e "${BOLD}📚 ARCHIVOS DE AYUDA DISPONIBLES:${NC}"
        echo ""
        
        if [ -f "README_FORK_CLEANUP.md" ]; then
            echo -e "  ${GREEN}✅${NC} README_FORK_CLEANUP.md ${CYAN}(★ EMPIEZA AQUÍ)${NC}"
            echo "     Resumen ejecutivo con visión general"
        fi
        
        if [ -f "QUICK_START_CLEANUP.md" ]; then
            echo -e "  ${GREEN}✅${NC} QUICK_START_CLEANUP.md ${CYAN}(★ RECOMENDADO)${NC}"
            echo "     Guía paso a paso con comandos listos"
        fi
        
        if [ -f "FORK_CLEANUP_GUIDE.md" ]; then
            echo -e "  ${GREEN}✅${NC} FORK_CLEANUP_GUIDE.md"
            echo "     Documentación completa y detallada"
        fi
        
        if [ -f "analyze_changes.sh" ]; then
            echo -e "  ${GREEN}✅${NC} analyze_changes.sh"
            echo "     Script para analizar cambios por funcionalidad"
        fi
        
        if [ -f "reorganize_fork_simple.sh" ]; then
            echo -e "  ${GREEN}✅${NC} reorganize_fork_simple.sh ${CYAN}(★ RECOMENDADO)${NC}"
            echo "     Script automatizado para reorganizar (método seguro)"
        fi
        
        if [ -f "reorganize_fork.sh" ]; then
            echo -e "  ${GREEN}✅${NC} reorganize_fork.sh"
            echo "     Script con más opciones (para usuarios avanzados)"
        fi
        
        echo ""
        echo -e "${BOLD}Para abrir cualquier archivo:${NC}"
        echo "  cat NOMBRE_ARCHIVO.md | less"
        echo "  code NOMBRE_ARCHIVO.md"
        echo ""
        ;;
        
    0)
        echo ""
        echo -e "${BLUE}👋 ¡Hasta luego!${NC}"
        echo ""
        exit 0
        ;;
        
    *)
        echo ""
        echo -e "${RED}❌ Opción inválida${NC}"
        exit 1
        ;;
esac

echo ""
