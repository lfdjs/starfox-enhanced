#!/usr/bin/env bash

set -Eeuo pipefail

cd "$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"

echo "============================================================"
echo "STAR FOX ENHANCED — DIAGNÓSTICO PRÉ-COMMIT"
echo "============================================================"
echo

echo "[1] Repositório:"
git rev-parse --show-toplevel

echo
echo "[2] Branch atual:"
git branch --show-current

echo
echo "[3] HEAD local:"
git rev-parse HEAD

echo
echo "[4] Atualizando referência remota..."
git fetch origin

echo
echo "[5] origin/main:"
git rev-parse origin/main

echo
echo "[6] Últimos commits locais:"
git --no-pager log \
    --oneline \
    --decorate \
    -8

echo
echo "[7] Status:"
git status --short

echo
echo "[8] Arquivos modificados:"
git diff --name-status

echo
echo "[9] Arquivos já staged:"
git diff --cached --name-status

echo
echo "[10] Resumo do diff:"
git diff --stat

echo
echo "[11] Verificação de whitespace:"
git diff --check || true

echo
echo "[12] Arquivos não rastreados:"
git ls-files \
    --others \
    --exclude-standard \
    | head -n 200

echo
echo "============================================================"
echo "DIAGNÓSTICO CONCLUÍDO"
echo "============================================================"
echo
echo "Nenhum commit foi criado."
echo "Nenhum push foi executado."
