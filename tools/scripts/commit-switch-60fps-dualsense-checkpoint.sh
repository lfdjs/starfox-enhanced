#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/commit-switch-checkpoint/$STAMP"

mkdir -p "$REPORT_DIR"

trap '
STATUS=$?
echo
echo "============================================================"
echo "SCRIPT INTERROMPIDO"
echo "============================================================"
echo "Código de saída: $STATUS"
echo "Linha aproximada: $LINENO"
echo
echo "O TERMINAL NÃO SERÁ FECHADO."
echo
exit $STATUS
' ERR


echo "============================================================"
echo "STAR FOX ENHANCED"
echo "CHECKPOINT — SWITCH 60 FPS + DUALSENSE"
echo "============================================================"
echo


# ============================================================
# 1. GIT / REMOTE
# ============================================================

echo "[1/11] Atualizando referência do GitHub..."

git fetch origin


BRANCH="$(git branch --show-current)"
LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse origin/main)"


echo
echo "Branch:"
echo "  $BRANCH"

echo
echo "HEAD local:"
echo "  $LOCAL_HEAD"

echo
echo "origin/main:"
echo "  $REMOTE_HEAD"


if [[ "$BRANCH" != "main" ]]
then
    echo
    echo "ERRO:"
    echo "A branch atual não é main."
    echo "Nenhuma alteração foi criada."
    return 20 2>/dev/null || exit 20
fi


if ! git merge-base --is-ancestor origin/main HEAD
then
    echo
    echo "ERRO:"
    echo "O histórico local não contém origin/main."
    echo "Não faremos rebase automaticamente."
    return 21 2>/dev/null || exit 21
fi


echo
echo "Histórico compatível: OK"


# ============================================================
# 2. ESTADO INICIAL
# ============================================================

echo
echo "============================================================"
echo "[2/11] ESTADO ATUAL"
echo "============================================================"

git status --short | tee "$REPORT_DIR/status-before.txt"

echo
echo "Diff rastreado:"
git diff --stat | tee "$REPORT_DIR/diff-before.txt"

echo
echo "Arquivos não rastreados:"
git ls-files \
    --others \
    --exclude-standard \
    | tee "$REPORT_DIR/untracked-before.txt"


# ============================================================
# 3. DIFF CHECK
# ============================================================

echo
echo "============================================================"
echo "[3/11] VALIDANDO CÓDIGO"
echo "============================================================"

git diff --check

echo "git diff --check: OK"


# ============================================================
# 4. BUILD DESKTOP
# ============================================================

echo
echo "============================================================"
echo "[4/11] BUILD DESKTOP RELEASE"
echo "============================================================"

BUILD_DESKTOP="$PROJECT_ROOT/build/linux-controller-checkpoint"

cmake \
    -S . \
    -B "$BUILD_DESKTOP" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_BUILD_SWITCH=OFF

cmake \
    --build "$BUILD_DESKTOP" \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-desktop.log"


# ============================================================
# 5. TESTES
# ============================================================

echo
echo "============================================================"
echo "[5/11] TESTES DESKTOP"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest.log"


# ============================================================
# 6. BUILD SWITCH
# ============================================================

echo
echo "============================================================"
echo "[6/11] BUILD NINTENDO SWITCH RELEASE"
echo "============================================================"

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

BUILD_SWITCH="$PROJECT_ROOT/build-switch"


"$DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake" \
    -S . \
    -B "$BUILD_SWITCH" \
    -DSTARFOX_BUILD_RUNTIME=OFF \
    -DSTARFOX_BUILD_TESTS=OFF \
    -DSTARFOX_BUILD_SWITCH=ON \
    -DCMAKE_BUILD_TYPE=Release


cmake \
    --build "$BUILD_SWITCH" \
    --target starfox_switch_nro \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-switch.log"


NRO="$BUILD_SWITCH/ports/switch/starfox_switch.nro"

test -s "$NRO"


echo
echo "NRO:"
ls -lh "$NRO"

echo
echo "Estrutura:"
grep -aob \
    'NRO0\|ASET' \
    "$NRO"

echo
echo "SHA256:"
sha256sum \
    "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"


# ============================================================
# 7. LIMPAR STAGING
# ============================================================

echo
echo "============================================================"
echo "[7/11] PREPARANDO STAGING SELETIVO"
echo "============================================================"

git reset


# ============================================================
# TRACKED MODIFICATIONS
#
# git add -u adiciona somente arquivos que já pertenciam
# ao repositório. Portanto não traz build/, out/, ROM etc.
# ============================================================

git add -u


# ============================================================
# NOVOS ARQUIVOS PERMITIDOS
#
# Incluímos somente áreas legítimas do projeto.
# ============================================================

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


# ============================================================
# REMOVER SCRIPTS TEMPORÁRIOS DESTE COMMIT
# ============================================================

git reset -- \
    tools/scripts/check-before-controller-commit.sh \
    tools/scripts/commit-switch-60fps-dualsense-checkpoint.sh \
    2>/dev/null || true


# ============================================================
# 8. PROTEÇÕES
# ============================================================

echo
echo "============================================================"
echo "[8/11] VERIFICAÇÕES DE SEGURANÇA"
echo "============================================================"


FORBIDDEN="$(
    git diff \
        --cached \
        --name-only \
    | grep -Ei \
        '\.(sfc|smc|rom|nes|n64|z64|v64|iso|xci|nsp|sav|srm|webm|mp4|mkv|log)$' \
    || true
)"


if [[ -n "$FORBIDDEN" ]]
then
    echo
    echo "ERRO:"
    echo "Arquivos que não devem entrar no Git foram encontrados:"
    echo
    echo "$FORBIDDEN"
    echo
    echo "Staging será limpo."
    git reset

    return 30 2>/dev/null || exit 30
fi


# Não permitir artefatos gerados.
GENERATED="$(
    git diff \
        --cached \
        --name-only \
    | grep -E \
        '(^|/)(build[^/]*|out)/' \
    || true
)"


if [[ -n "$GENERATED" ]]
then
    echo
    echo "ERRO:"
    echo "Artefatos de build encontrados:"
    echo
    echo "$GENERATED"

    git reset

    return 31 2>/dev/null || exit 31
fi


echo "ROMs / saves / vídeos / logs: OK"
echo "Build / out: OK"


# ============================================================
# 9. REVISÃO DO STAGING
# ============================================================

echo
echo "============================================================"
echo "[9/11] CONTEÚDO DO COMMIT"
echo "============================================================"

git diff \
    --cached \
    --name-status \
    | tee "$REPORT_DIR/staged-files.txt"


echo
echo "Resumo:"
git diff \
    --cached \
    --stat \
    | tee "$REPORT_DIR/staged-stat.txt"


git diff --cached --check


if git diff --cached --quiet
then
    echo
    echo "Nenhuma alteração para commit."
    echo
    echo "Últimos commits:"
    git --no-pager log \
        --oneline \
        --decorate \
        -6

    return 0 2>/dev/null || exit 0
fi


# ============================================================
# 10. COMMIT
# ============================================================

echo
echo "============================================================"
echo "[10/11] CRIANDO CHECKPOINT"
echo "============================================================"


git commit \
    -s \
    -m "Switch: stabilize 60 FPS and refine DualSense controls"


COMMIT_SHA="$(git rev-parse HEAD)"


echo
echo "Commit:"
echo "  $COMMIT_SHA"


git --no-pager show \
    --stat \
    --oneline \
    HEAD \
    | tee "$REPORT_DIR/commit.txt"


# ============================================================
# 11. PUSH
# ============================================================

echo
echo "============================================================"
echo "[11/11] PUSH PARA origin/main"
echo "============================================================"


git push origin main


echo
echo "============================================================"
echo "CHECKPOINT CONCLUÍDO COM SUCESSO"
echo "============================================================"

echo
echo "Commit:"
echo "  $COMMIT_SHA"

echo
echo "GitHub main:"
git ls-remote \
    origin \
    refs/heads/main

echo
echo "Working tree restante:"
git status --short


{
    echo "STAR FOX ENHANCED"
    echo "Switch 60 FPS + DualSense checkpoint"
    echo
    echo "Commit:"
    echo "  $COMMIT_SHA"
    echo
    echo "NRO SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
} > "$REPORT_DIR/report-share.txt"


echo
echo "Relatório local:"
echo "  $REPORT_DIR/report-share.txt"

echo
echo "Pode copiar o hash acima para o ChatGPT."
