#!/bin/bash
# Script para analizar cambios por funcionalidad en el fork

cd /workspaces/ubuntu/chatwoot

echo "=========================================="
echo "  ANÁLISIS DE CAMBIOS POR FUNCIONALIDAD"
echo "=========================================="
echo ""

# Encontrar el commit base
echo "🔍 Encontrando commit base..."
BASE_COMMIT=$(git merge-base develop upstream/develop)
echo "📌 Commit base: $BASE_COMMIT"
echo ""

echo "=========================================="
echo "📊 RESUMEN GENERAL"
echo "=========================================="
TOTAL_FILES=$(git diff $BASE_COMMIT HEAD --name-only | wc -l)
TOTAL_ADDITIONS=$(git diff $BASE_COMMIT HEAD --shortstat | grep -oP '\d+(?= insertion)')
TOTAL_DELETIONS=$(git diff $BASE_COMMIT HEAD --shortstat | grep -oP '\d+(?= deletion)')
echo "📁 Total archivos modificados: $TOTAL_FILES"
echo "➕ Total líneas agregadas: ${TOTAL_ADDITIONS:-0}"
echo "➖ Total líneas eliminadas: ${TOTAL_DELETIONS:-0}"
echo ""

# Función para contar archivos y cambios
analyze_feature() {
    local feature_name=$1
    local pattern=$2
    
    echo "=========================================="
    echo "🎯 $feature_name"
    echo "=========================================="
    
    local files=$(git diff $BASE_COMMIT HEAD --name-only | grep -iE "$pattern")
    local count=$(echo "$files" | grep -v '^$' | wc -l)
    
    if [ $count -gt 0 ]; then
        echo "📁 Archivos modificados: $count"
        echo ""
        echo "$files" | while read file; do
            if [ ! -z "$file" ]; then
                local stats=$(git diff $BASE_COMMIT HEAD --shortstat -- "$file")
                echo "  📄 $file"
                if [ ! -z "$stats" ]; then
                    echo "     $stats"
                fi
            fi
        done
    else
        echo "❌ No se encontraron archivos modificados"
    fi
    echo ""
}

# Analizar cada funcionalidad
analyze_feature "STORAGE MANAGEMENT" "storage"
analyze_feature "WAHA INTEGRATION" "waha"
analyze_feature "WHATSAPP CALLS" "(whatsapp.*(call|p2p))|(call.*whatsapp)"
analyze_feature "CANNED RESPONSES" "canned"
analyze_feature "N8N INTEGRATION" "n8n"
analyze_feature "TEMPLATES & REACTIONS" "template|reaction"

echo "=========================================="
echo "📝 ARCHIVOS DE CONFIGURACIÓN MODIFICADOS"
echo "=========================================="
git diff $BASE_COMMIT HEAD --name-only | grep -E "(config/|Gemfile|package\.json|\.yml$|\.yaml$)" | while read file; do
    echo "  📄 $file"
done
echo ""

echo "=========================================="
echo "🧪 ARCHIVOS DE PRUEBAS MODIFICADOS"
echo "=========================================="
git diff $BASE_COMMIT HEAD --name-only | grep -E "(spec/|test/|\.test\.|\.spec\.)" | while read file; do
    echo "  📄 $file"
done
echo ""

echo "=========================================="
echo "📚 DOCUMENTACIÓN MODIFICADA"
echo "=========================================="
git diff $BASE_COMMIT HEAD --name-only | grep -E "(\.md$|docs/)" | while read file; do
    echo "  📄 $file"
done
echo ""

echo "=========================================="
echo "🌐 TRADUCCIONES (i18n)"
echo "=========================================="
git diff $BASE_COMMIT HEAD --name-only | grep -E "(locale|i18n|lang)" | while read file; do
    echo "  📄 $file"
done
echo ""

echo "=========================================="
echo "🔧 OTROS ARCHIVOS MODIFICADOS"
echo "=========================================="
# Archivos que no coinciden con ninguna categoría anterior
git diff $BASE_COMMIT HEAD --name-only | \
    grep -vE "(storage|waha|call|canned|n8n|template|reaction|config/|spec/|test/|\.md$|docs/|locale|i18n)" | \
    head -20 | while read file; do
    echo "  📄 $file"
done
echo ""

echo "=========================================="
echo "✅ ANÁLISIS COMPLETADO"
echo "=========================================="
echo ""
echo "💡 Próximos pasos:"
echo "   1. Revisa los archivos listados arriba"
echo "   2. Agrupa los cambios por funcionalidad"
echo "   3. Sigue la guía en FORK_CLEANUP_GUIDE.md"
echo ""
