#!/usr/bin/env bash

set -uo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"

UPSTREAM_DIR="$PROJECT_ROOT/upstream-ultrastarfox"

UPSTREAM_URL="https://github.com/Sunlitspace542/ultrastarfox.git"

EXPECTED_COMMIT="270e959a47d82240d9290a6c6630032c9ec53ff5"

REPORT_ROOT="$PROJECT_ROOT/out/linux-upstream-reports"
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
        echo "STAR FOX ENHANCED — ULTRASTARFOX LINUX BUILD"
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
            "$UPSTREAM_DIR/SF.SFC" \
            "$UPSTREAM_DIR/SYMBOLS.TXT" \
            "$UPSTREAM_DIR/BANKS.CSV"
        do
            if [[ -s "$file" ]]; then
                printf 'OK      %-12s %s bytes\n' \
                    "$(basename "$file")" \
                    "$(stat -c '%s' "$file")"
            else
                printf 'AUSENTE %s\n' "$file"
            fi
        done

        echo
        echo "Git:"
        if [[ -d "$UPSTREAM_DIR/.git" ]]; then
            git -C "$UPSTREAM_DIR" status --short 2>/dev/null || true
            echo
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
        echo "ÚLTIMAS 160 LINHAS DO BUILD"
        line

        tail -n 160 "$FULL_LOG" 2>/dev/null || true

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

section "STAR FOX ENHANCED — ULTRASTARFOX BUILD LINUX"

echo "Projeto:"
echo "  $PROJECT_ROOT"
echo
echo "Checkout:"
echo "  $UPSTREAM_DIR"
echo
echo "Commit:"
echo "  $EXPECTED_COMMIT"

# ============================================================
# ETAPA 1 — dependências básicas
# ============================================================

section "ETAPA 1 — DEPENDÊNCIAS"

MISSING=0

for cmd in git make; do

    if command_exists "$cmd"; then
        echo "OK      $cmd -> $(command -v "$cmd")"
    else
        echo "AUSENTE $cmd"
        MISSING=1
    fi

done

if [[ "$MISSING" -ne 0 ]]; then

    echo
    echo "Instalando ferramentas básicas..."

    sudo apt-get update || {
        fail 10 "apt-get update falhou"
        exit "$FINAL_RC"
    }

    sudo apt-get install -y \
        git \
        make \
        snapd || {
            fail 11 "instalação das dependências falhou"
            exit "$FINAL_RC"
        }

fi

# ============================================================
# ETAPA 2 — DOSBox-X
# ============================================================

section "ETAPA 2 — DOSBOX-X"

# Snap normalmente instala os binários aqui.
export PATH="/snap/bin:$PATH"

if command_exists dosbox-x; then

    echo "DOSBox-X já disponível:"
    command -v dosbox-x

else

    echo "DOSBox-X não encontrado."
    echo "Tentando instalar pelo Snap..."

    if ! command_exists snap; then

        sudo apt-get update || {
            fail 20 "apt-get update falhou"
            exit "$FINAL_RC"
        }

        sudo apt-get install -y snapd || {
            fail 21 "não foi possível instalar snapd"
            exit "$FINAL_RC"
        }

    fi

    sudo snap install dosbox-x || {

        # Pode retornar erro se já estiver instalado.
        if snap list dosbox-x >/dev/null 2>&1; then
            echo "DOSBox-X já consta como instalado."
        else
            fail 22 "não foi possível instalar DOSBox-X"
            exit "$FINAL_RC"
        fi
    }

fi

export PATH="/snap/bin:$PATH"

if ! command_exists dosbox-x; then
    fail 23 "dosbox-x continua indisponível após instalação"
    exit "$FINAL_RC"
fi

echo
echo "DOSBox-X:"
command -v dosbox-x

dosbox-x -version 2>&1 | head -n 20 || true

# ============================================================
# ETAPA 3 — clone
# ============================================================

section "ETAPA 3 — CHECKOUT ULTRASTARFOX"

if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then

    echo "Clonando:"
    echo "$UPSTREAM_URL"

    git clone \
        "$UPSTREAM_URL" \
        "$UPSTREAM_DIR" || {
            fail 30 "git clone falhou"
            exit "$FINAL_RC"
        }

else

    echo "Checkout já existe."
    echo
    echo "Remote:"
    git -C "$UPSTREAM_DIR" remote -v
    echo
    echo "Commit atual:"
    git -C "$UPSTREAM_DIR" rev-parse HEAD

fi

# ============================================================
# ETAPA 4 — verificar alterações locais
# ============================================================

section "ETAPA 4 — ESTADO DO CHECKOUT"

DIRTY="$(
    git -C "$UPSTREAM_DIR" \
        status \
        --porcelain \
        --untracked-files=no
)"

if [[ -n "$DIRTY" ]]; then

    echo "Existem alterações versionadas no checkout:"
    echo
    echo "$DIRTY"
    echo
    echo "O script não fará checkout automático para evitar"
    echo "sobrescrever alterações locais."

    fail 40 "checkout UltraStarFox possui alterações locais"
    exit "$FINAL_RC"

fi

echo "Checkout sem alterações versionadas."

# ============================================================
# ETAPA 5 — commit fixado
# ============================================================

section "ETAPA 5 — SINCRONIZAÇÃO DO COMMIT"

echo "Atualizando objetos Git..."

git -C "$UPSTREAM_DIR" \
    fetch \
    --all \
    --tags || {
        fail 50 "git fetch falhou"
        exit "$FINAL_RC"
    }

echo
echo "Selecionando:"
echo "$EXPECTED_COMMIT"

git -C "$UPSTREAM_DIR" \
    checkout \
    --detach \
    "$EXPECTED_COMMIT" || {
        fail 51 "checkout do commit fixado falhou"
        exit "$FINAL_RC"
    }

ACTUAL_COMMIT="$(
    git -C "$UPSTREAM_DIR" rev-parse HEAD
)"

echo
echo "Commit atual:"
echo "$ACTUAL_COMMIT"

if [[ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]]; then
    fail 52 "commit atual não corresponde ao esperado"
    exit "$FINAL_RC"
fi

echo
echo "Commit validado."

# ============================================================
# ETAPA 6 — validar Makefile Linux
# ============================================================

section "ETAPA 6 — MAKEFILE"

if [[ ! -s "$UPSTREAM_DIR/Makefile" ]]; then
    fail 60 "Makefile não encontrado"
    exit "$FINAL_RC"
fi

echo "Makefile:"
sed -n '1,120p' "$UPSTREAM_DIR/Makefile"

echo
echo "Comando DOSBox-X resolvido:"
command -v dosbox-x

# ============================================================
# ETAPA 7 — limpar outputs anteriores
# ============================================================

section "ETAPA 7 — PREPARAÇÃO DO BUILD"

for file in \
    "$UPSTREAM_DIR/SF.SFC" \
    "$UPSTREAM_DIR/SYMBOLS.TXT" \
    "$UPSTREAM_DIR/BANKS.CSV"
do

    if [[ -f "$file" ]]; then
        echo "Removendo output anterior:"
        echo "  $file"
        rm -f "$file"
    fi

done

# ============================================================
# ETAPA 8 — build
# ============================================================

section "ETAPA 8 — BUILD ULTRASTARFOX"

cd "$UPSTREAM_DIR" || {
    fail 70 "não foi possível entrar no checkout"
    exit "$FINAL_RC"
}

echo "Executando:"
echo
echo "  make WINE=0"
echo

make WINE=0

MAKE_RC=$?

echo
echo "Código do make: $MAKE_RC"

if [[ "$MAKE_RC" -ne 0 ]]; then
    fail 71 "build UltraStarFox falhou"
    exit "$FINAL_RC"
fi

# ============================================================
# ETAPA 9 — outputs
# ============================================================

section "ETAPA 9 — VALIDAÇÃO DOS OUTPUTS"

OUTPUT_ERROR=0

for file in \
    "$UPSTREAM_DIR/SF.SFC" \
    "$UPSTREAM_DIR/SYMBOLS.TXT" \
    "$UPSTREAM_DIR/BANKS.CSV"
do

    if [[ -s "$file" ]]; then

        echo "OK:"
        ls -lh "$file"

    else

        echo "AUSENTE:"
        echo "$file"

        OUTPUT_ERROR=1
    fi

done

if [[ "$OUTPUT_ERROR" -ne 0 ]]; then
    fail 80 "build terminou, mas um ou mais outputs não foram produzidos"
    exit "$FINAL_RC"
fi

# ============================================================
# ETAPA 10 — hashes
# ============================================================

section "ETAPA 10 — HASHES"

sha256sum \
    "$UPSTREAM_DIR/SF.SFC" \
    "$UPSTREAM_DIR/SYMBOLS.TXT" \
    "$UPSTREAM_DIR/BANKS.CSV"

# ============================================================
# ETAPA 11 — integração com starfox-enhanced
# ============================================================

section "ETAPA 11 — INTEGRAÇÃO"

cd "$PROJECT_ROOT" || exit 90

echo "Assets que starfox-enhanced espera:"
echo

for file in \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT
do

    if [[ -s "$file" ]]; then
        echo "OK      $file"
    else
        echo "AUSENTE $file"
        FINAL_RC=91
    fi

done

if [[ "$FINAL_RC" -ne 0 ]]; then
    exit "$FINAL_RC"
fi

section "BUILD ULTRASTARFOX CONCLUÍDO"

echo "Os assets Original estão prontos."
echo
echo "ROM:"
echo "  $UPSTREAM_DIR/SF.SFC"
echo
echo "Símbolos:"
echo "  $UPSTREAM_DIR/SYMBOLS.TXT"
echo
echo "Próximo comando:"
echo
echo "  cd \"$PROJECT_ROOT\""
echo "  ./tools/scripts/setup-linux.sh --no-install-deps"

exit 0