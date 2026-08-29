#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"
SOURCE="$PROJECT_ROOT/tests/dialogue_catalog_tests.cpp"

cd "$PROJECT_ROOT"

echo "============================================================"
echo "STAR FOX ENHANCED — FIX PT-BR FASE 03"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

path = Path("tests/dialogue_catalog_tests.cpp")
text = path.read_text(encoding="utf-8")

old = r'''            << "0xabcdef\tLinha um\\\\nLinha dois\n";'''
new = r'''            << "0xabcdef\tLinha um\\nLinha dois\n";'''

if new in text:
    print("Teste de newline já está corrigido.")

elif old not in text:
    raise RuntimeError(
        "Não encontrei o trecho esperado em dialogue_catalog_tests.cpp"
    )

else:
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print("Teste de newline corrigido.")

updated = path.read_text(encoding="utf-8")

if r'Linha um\\nLinha dois' not in updated:
    raise RuntimeError(
        "Validação final falhou: sequência \\n correta não encontrada."
    )

print("Validação estrutural: OK")
PY

echo
echo "============================================================"
echo "DIFF CHECK"
echo "============================================================"

git diff --check

echo
echo "Trecho corrigido:"

grep -n -A3 -B3 \
    'Linha um' \
    tests/dialogue_catalog_tests.cpp

echo
echo "============================================================"
echo "BUILD INCREMENTAL"
echo "============================================================"

cmake \
    --build "$BUILD_DIR" \
    -j"$(nproc)"

echo
echo "============================================================"
echo "TESTE DO CATALOGO"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DIR" \
    -R '^starfox_dialogue_catalog_tests$' \
    --output-on-failure

echo
echo "============================================================"
echo "SUITE COMPLETA"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"

echo
echo "Correção concluída."
echo
echo "Esperado:"
echo "  18/18 testes passando"
