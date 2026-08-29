#!/usr/bin/env bash

set -uo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"

UPSTREAM_DIR="$PROJECT_ROOT/upstream-star-fox-ex"
UPSTREAM_URL="https://github.com/sunlitspace542/star-fox-ex.git"

EXPECTED_COMMIT="b5e2d837a15a72a532cd019bfe332b7a4b660924"

EX_ROM="$UPSTREAM_DIR/SFES/SFES.SFC"
EX_SYMBOLS="$UPSTREAM_DIR/SYMBOLS.TXT"
EX_BANKS="$UPSTREAM_DIR/BANKS.CSV"

REPORT_ROOT="$PROJECT_ROOT/out/linux-starfox-ex-reports"
STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$REPORT_ROOT/$STAMP"

FULL_LOG="$REPORT_DIR/full.log"
SUMMARY="$REPORT_DIR/summary.txt"
SHARE="$REPORT_DIR/report-share.txt"

mkdir -p "$REPORT_DIR"

exec > >(tee -a "$FULL_LOG") 2>&1

FINAL_RC=0

line() {
    printf '%s\n' \
        "============================================================"
}

section() {
    echo
    line
    echo "$1"
    line
}

fail() {
    local code="$1"
    shift

    echo
    echo "ERRO: $*"

    FINAL_RC="$code"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

generate_report() {

    {
        echo "STAR FOX ENHANCED — STAR FOX EX LINUX BUILD"
        echo
        echo "Data:            $(date --iso-8601=seconds 2>/dev/null || date)"
        echo "Projeto:         $PROJECT_ROOT"
        echo "Upstream:        $UPSTREAM_DIR"
        echo "Commit esperado: $EXPECTED_COMMIT"
        echo "Código final:    $FINAL_RC"
        echo

        echo "OUTPUTS"
        echo "------------------------------------------------------------"

        for file in \
            "$EX_ROM" \
            "$EX_SYMBOLS" \
            "$EX_BANKS"
        do
            if [[ -s "$file" ]]; then
                printf 'OK      %-18s %s bytes\n' \
                    "$(basename "$file")" \
                    "$(stat -c '%s' "$file")"
            else
                printf 'AUSENTE %s\n' "$file"
            fi
        done

        echo
        echo "GIT"
        echo "------------------------------------------------------------"

        if [[ -d "$UPSTREAM_DIR/.git" ]]; then
            echo "Commit:"
            git -C "$UPSTREAM_DIR" rev-parse HEAD 2>/dev/null || true
            echo

            echo "Status:"
            git -C "$UPSTREAM_DIR" status --short 2>/dev/null || true
            echo

            echo "Último commit:"
            git -C "$UPSTREAM_DIR" log -1 --oneline 2>/dev/null || true
        fi

        echo
        echo "Relatório completo:"
        echo "$FULL_LOG"

    } > "$SUMMARY"

    {
        cat "$SUMMARY"

        echo
        echo
        line
        echo "ÚLTIMAS 200 LINHAS"
        line

        tail -n 200 "$FULL_LOG" 2>/dev/null || true

    } > "$SHARE"

    echo
    line
    echo "RELATÓRIOS"
    line
    echo
    echo "Resumo:"
    echo "  $SUMMARY"
    echo
    echo "Para enviar ao ChatGPT:"
    echo "  $SHARE"
    echo
    echo "Log completo:"
    echo "  $FULL_LOG"
}

on_exit() {

    local rc=$?

    trap - EXIT

    if [[ "$FINAL_RC" -eq 0 && "$rc" -ne 0 ]]; then
        FINAL_RC="$rc"
    fi

    generate_report

    exit "$FINAL_RC"
}

trap on_exit EXIT

section "STAR FOX ENHANCED — BUILD STAR FOX EX NO LINUX"

echo "Projeto:"
echo "  $PROJECT_ROOT"
echo
echo "Checkout:"
echo "  $UPSTREAM_DIR"
echo
echo "Commit obrigatório:"
echo "  $EXPECTED_COMMIT"

# ============================================================
# ETAPA 1 — ferramentas
# ============================================================

section "ETAPA 1 — FERRAMENTAS"

export PATH="/snap/bin:$PATH"

MISSING=0

for cmd in \
    git \
    dosbox-x
do

    if command_exists "$cmd"; then
        echo "OK      $cmd -> $(command -v "$cmd")"
    else
        echo "AUSENTE $cmd"
        MISSING=1
    fi

done

if [[ "$MISSING" -ne 0 ]]; then
    fail 10 "git ou DOSBox-X não estão disponíveis"
    exit "$FINAL_RC"
fi

echo
dosbox-x -version 2>&1 | head -n 10 || true

# ============================================================
# ETAPA 2 — checkout
# ============================================================

section "ETAPA 2 — CHECKOUT STAR FOX EX"

if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then

    echo "Clonando:"
    echo "  $UPSTREAM_URL"
    echo

    git clone \
        "$UPSTREAM_URL" \
        "$UPSTREAM_DIR"

    CLONE_RC=$?

    if [[ "$CLONE_RC" -ne 0 ]]; then
        fail 20 "não foi possível clonar o repositório Star Fox EX"
        exit "$FINAL_RC"
    fi

else

    echo "Checkout já existe."
    echo

    git -C "$UPSTREAM_DIR" remote -v

fi

# ============================================================
# ETAPA 3 — proteger alterações locais
# ============================================================

section "ETAPA 3 — VERIFICAÇÃO DO CHECKOUT"

DIRTY="$(
    git -C "$UPSTREAM_DIR" \
        status \
        --porcelain \
        --untracked-files=no
)"

if [[ -n "$DIRTY" ]]; then

    echo "Existem alterações versionadas:"
    echo
    echo "$DIRTY"
    echo
    echo "O script não fará checkout automático."

    fail 30 "checkout Star Fox EX possui alterações locais"
    exit "$FINAL_RC"

fi

echo "Nenhuma alteração versionada detectada."

# ============================================================
# ETAPA 4 — commit fixado
# ============================================================

section "ETAPA 4 — COMMIT FIXADO"

git -C "$UPSTREAM_DIR" \
    fetch \
    --all \
    --tags

FETCH_RC=$?

if [[ "$FETCH_RC" -ne 0 ]]; then
    fail 40 "git fetch falhou"
    exit "$FINAL_RC"
fi

git -C "$UPSTREAM_DIR" \
    checkout \
    --detach \
    "$EXPECTED_COMMIT"

CHECKOUT_RC=$?

if [[ "$CHECKOUT_RC" -ne 0 ]]; then
    fail 41 "não foi possível selecionar o commit esperado"
    exit "$FINAL_RC"
fi

ACTUAL_COMMIT="$(
    git -C "$UPSTREAM_DIR" rev-parse HEAD
)"

echo
echo "Esperado:"
echo "  $EXPECTED_COMMIT"
echo
echo "Atual:"
echo "  $ACTUAL_COMMIT"

if [[ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]]; then
    fail 42 "commit atual diverge do exigido"
    exit "$FINAL_RC"
fi

echo
echo "Commit validado."

# ============================================================
# ETAPA 5 — inventário da toolchain
# ============================================================

section "ETAPA 5 — INVENTÁRIO"

echo "Raiz do upstream:"
echo

find "$UPSTREAM_DIR" \
    -maxdepth 2 \
    -type f \
    \( \
        -iname '*.bat' \
        -o \
        -iname '*.cmd' \
        -o \
        -iname 'Makefile' \
        -o \
        -iname 'makefile' \
        -o \
        -iname 'dosbox-x.exe' \
    \) \
    -printf '%P\n' \
    | sort

echo
echo "Diretório BIN, se existente:"
echo

if [[ -d "$UPSTREAM_DIR/BIN" ]]; then
    find "$UPSTREAM_DIR/BIN" \
        -maxdepth 1 \
        -type f \
        -printf '%f\n' \
        | sort \
        | head -n 100
else
    echo "BIN não encontrado."
fi

# ============================================================
# ETAPA 6 — preparar batch equivalente ao PowerShell
# ============================================================

section "ETAPA 6 — SCRIPT DOS"

BATCH="$UPSTREAM_DIR/.starfox-port-ex-linux-build.bat"
SUCCESS="$UPSTREAM_DIR/.starfox-port-ex-linux-build.ok"

rm -f \
    "$BATCH" \
    "$SUCCESS"

cat > "$BATCH" <<'BAT_EOF'
@echo off
set path=%path%;c:\bin
set sasmheap=14400

cd sfes

make clean
if errorlevel 1 goto failed

make hardware=0 newface=1
if errorlevel 1 goto failed

copy sfes.sfc ..\sfes.sfc
if errorlevel 1 goto failed

cd ..

echo ok>.starfox-port-ex-linux-build.ok

exit

:failed
cd ..
exit
BAT_EOF

echo "Batch criado:"
echo "  $BATCH"
echo

cat "$BATCH"

# ============================================================
# ETAPA 7 — limpar outputs
# ============================================================

section "ETAPA 7 — LIMPEZA DE OUTPUTS"

rm -f \
    "$EX_ROM" \
    "$UPSTREAM_DIR/SFES.SFC" \
    "$EX_SYMBOLS" \
    "$EX_BANKS" \
    "$SUCCESS"

echo "Outputs antigos removidos."

# ============================================================
# ETAPA 8 — executar DOSBox-X
# ============================================================

section "ETAPA 8 — BUILD STAR FOX EX"

cd "$UPSTREAM_DIR" || {
    fail 80 "não foi possível entrar no checkout"
    exit "$FINAL_RC"
}

echo "Executando DOSBox-X:"
echo
echo "  dosbox-x -fastlaunch -nolog $(basename "$BATCH")"
echo

dosbox-x \
    -fastlaunch \
    -nolog \
    "$(basename "$BATCH")"

DOSBOX_RC=$?

echo
echo "Código DOSBox-X:"
echo "  $DOSBOX_RC"

# Alguns programas DOS não propagam de forma confiável o status
# final ao host; por isso também usamos o arquivo sentinel.

if [[ ! -s "$SUCCESS" ]]; then

    echo
    echo "Arquivo de sucesso não foi produzido:"
    echo "  $SUCCESS"

    fail 81 "assembler Star Fox EX não concluiu"
    exit "$FINAL_RC"

fi

echo
echo "Sentinel de build encontrado:"
cat "$SUCCESS"

# ============================================================
# ETAPA 9 — validar outputs
# ============================================================

section "ETAPA 9 — OUTPUTS"

OUTPUT_ERROR=0

for file in \
    "$EX_ROM" \
    "$EX_SYMBOLS" \
    "$EX_BANKS"
do

    if [[ -s "$file" ]]; then

        echo "OK:"
        ls -lh "$file"

    else

        echo "AUSENTE:"
        echo "  $file"

        OUTPUT_ERROR=1

    fi

done

if [[ "$OUTPUT_ERROR" -ne 0 ]]; then
    fail 90 "um ou mais outputs Star Fox EX estão ausentes"
    exit "$FINAL_RC"
fi

# ============================================================
# ETAPA 10 — hashes
# ============================================================

section "ETAPA 10 — HASHES"

sha256sum \
    "$EX_ROM" \
    "$EX_SYMBOLS" \
    "$EX_BANKS"

# ============================================================
# ETAPA 11 — integração
# ============================================================

section "ETAPA 11 — INTEGRAÇÃO COM STARFOX-ENHANCED"

cd "$PROJECT_ROOT" || {
    fail 100 "não foi possível retornar ao projeto"
    exit "$FINAL_RC"
}

for file in \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    upstream-star-fox-ex/SFES/SFES.SFC \
    upstream-star-fox-ex/SYMBOLS.TXT
do

    if [[ -s "$file" ]]; then
        echo "OK      $file"
    else
        echo "AUSENTE $file"
        FINAL_RC=101
    fi

done

if [[ "$FINAL_RC" -ne 0 ]]; then
    exit "$FINAL_RC"
fi

# ============================================================
# Limpeza temporária
# ============================================================

rm -f \
    "$BATCH" \
    "$SUCCESS"

section "BUILD STAR FOX EX CONCLUÍDO"

echo "Original + Star Fox EX estão disponíveis."
echo
echo "Próximo comando:"
echo
echo "  cd \"$PROJECT_ROOT\""
echo "  ./tools/scripts/setup-linux.sh --no-install-deps"

exit 0
