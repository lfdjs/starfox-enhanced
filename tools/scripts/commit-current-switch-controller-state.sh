#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
cd "$PROJECT_ROOT"

trap '
STATUS=$?
echo
echo "============================================================"
echo "SCRIPT INTERROMPIDO"
echo "============================================================"
echo "Código: $STATUS"
echo "O terminal continuará aberto."
exit $STATUS
' ERR

echo "============================================================"
echo "STAR FOX ENHANCED"
echo "CHECKPOINT DO ESTADO ATUAL"
echo "============================================================"
echo

echo "[1/7] Atualizando referência remota..."
git fetch origin

echo
echo "Branch:"
git branch --show-current

echo
echo "HEAD local:"
git rev-parse HEAD

echo
echo "origin/main:"
git rev-parse origin/main

if [[ "$(git branch --show-current)" != "main" ]]
then
    echo
    echo "ERRO: a branch atual não é main."
    exit 20
fi

if ! git merge-base --is-ancestor origin/main HEAD
then
    echo
    echo "ERRO: origin/main não pertence ao histórico local."
    echo "Nenhum commit será criado."
    exit 21
fi

echo
echo "============================================================"
echo "[2/7] ESTADO ATUAL"
echo "============================================================"

git status --short

echo
echo "Diff:"
git diff --stat

echo
echo "============================================================"
echo "[3/7] VALIDAÇÃO BÁSICA"
echo "============================================================"

git diff --check

echo "git diff --check: OK"

echo
echo "============================================================"
echo "[4/7] PREPARANDO STAGING"
echo "============================================================"

git reset

# Arquivos já rastreados modificados.
git add -u

# Novos arquivos legítimos do projeto.
SAFE_PATHS=(
    "CMakeLists.txt"
    "cmake"
    "include"
    "src"
    "tests"
    "ports"
    "assets"
    "resources"
    "data"
    "tools/scripts"
)

for path in "${SAFE_PATHS[@]}"
do
    if [[ -e "$path" ]]
    then
        git add -- "$path"
    fi
done

# Scripts temporários/operacionais que não queremos versionar.
TEMP_SCRIPTS=(
    "tools/scripts/check-before-controller-commit.sh"
    "tools/scripts/commit-switch-60fps-dualsense-checkpoint.sh"
    "tools/scripts/fix-steamdeck-gamepad-detection.sh"
    "tools/scripts/commit-current-switch-controller-state.sh"
)

for file in "${TEMP_SCRIPTS[@]}"
do
    git reset -- "$file" 2>/dev/null || true
done

echo
echo "============================================================"
echo "[5/7] SEGURANÇA DO COMMIT"
echo "============================================================"

FORBIDDEN="$(
    git diff --cached --name-only \
    | grep -Ei '\.(sfc|smc|rom|nes|n64|z64|v64|iso|xci|nsp|sav|srm|log|webm|mp4|mkv)$' \
    || true
)"

if [[ -n "$FORBIDDEN" ]]
then
    echo
    echo "ERRO: arquivos proibidos encontrados no staging:"
    echo "$FORBIDDEN"
    echo
    echo "Staging será limpo."
    git reset
    exit 30
fi

GENERATED="$(
    git diff --cached --name-only \
    | grep -E '(^|/)(build[^/]*|out)/' \
    || true
)"

if [[ -n "$GENERATED" ]]
then
    echo
    echo "ERRO: artefatos de build encontrados:"
    echo "$GENERATED"
    git reset
    exit 31
fi

git diff --cached --check

echo
echo "Arquivos que entrarão no commit:"
git diff --cached --name-status

echo
echo "Resumo:"
git diff --cached --stat

if git diff --cached --quiet
then
    echo
    echo "Não há alterações para commit."
    exit 0
fi

echo
echo "============================================================"
echo "[6/7] CRIANDO COMMIT"
echo "============================================================"

git commit \
    -s \
    -m "Checkpoint: Switch 60 FPS and PlayStation controller visuals" \
    -m "Current working checkpoint with Switch performance optimizations and dynamic controller visuals, including DualSense work. Known unrelated Steam Deck runtime-input test remains unresolved."

COMMIT_SHA="$(git rev-parse HEAD)"

echo
echo "Commit criado:"
echo "  $COMMIT_SHA"

git --no-pager show \
    --stat \
    --oneline \
    HEAD

echo
echo "============================================================"
echo "[7/7] PUSH"
echo "============================================================"

git push origin main

echo
echo "============================================================"
echo "CHECKPOINT CONCLUÍDO"
echo "============================================================"

echo
echo "Commit:"
echo "  $COMMIT_SHA"

echo
echo "origin/main:"
git ls-remote origin refs/heads/main

echo
echo "Últimos commits:"
git --no-pager log \
    --oneline \
    --decorate \
    -6

echo
echo "Arquivos locais restantes:"
git status --short

echo
echo "Observação:"
echo "  starfox_runtime_input_tests possui falha conhecida"
echo "  relacionada à identificação virtual de Steam Deck."
echo "  Este checkpoint não tenta corrigir essa funcionalidade."
