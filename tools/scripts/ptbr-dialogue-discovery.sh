#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"

OUTPUT_DIR="$PROJECT_ROOT/out/ptbr-dialogue-discovery/$STAMP"

mkdir -p "$OUTPUT_DIR"

LOG="$OUTPUT_DIR/runtime.log"
ADDRESSES="$OUTPUT_DIR/addresses.txt"
COMMANDS="$OUTPUT_DIR/probe-commands.txt"

echo "============================================================"
echo "STAR FOX ENHANCED — DESCOBERTA DE DIALOGOS PT-BR"
echo "============================================================"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Jogue normalmente."
echo "Ao terminar, feche a janela do jogo."
echo

set +e

STARFOX_LOG_MISSING_TRANSLATIONS=1 \
STARFOX_TEST_LANGUAGE=PT_BR \
"$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    BOOT \
    2> >(tee "$LOG" >&2)

GAME_RC=$?

set -e

grep \
    'PT-BR missing dialogue:' \
    "$LOG" \
    | sed 's/.*0x/0x/' \
    | tr '[:lower:]' '[:upper:]' \
    | sort -u \
    > "$ADDRESSES" \
    || true

: > "$COMMANDS"

while IFS= read -r address
do
    [[ -z "$address" ]] && continue

    printf \
        './tools/scripts/ptbr-dialogue-probe.sh %s\n' \
        "$address" \
        >> "$COMMANDS"

done < "$ADDRESSES"

COUNT="$(
    grep -c . "$ADDRESSES" \
        2>/dev/null \
        || true
)"

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"
echo
echo "Código do jogo:"
echo "  $GAME_RC"
echo
echo "Diálogos distintos encontrados:"
echo "  $COUNT"
echo
echo "Endereços:"
echo "  $ADDRESSES"
echo
echo "Comandos de inspeção:"
echo "  $COMMANDS"
echo

if [[ -s "$ADDRESSES" ]]; then
    cat "$ADDRESSES"

    echo
    echo "Para examinar uma fala:"
    echo
    head -n 1 "$COMMANDS"
else
    echo "Nenhum diálogo não traduzido foi encontrado nesta execução."
fi

exit 0
