#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

cd "$PROJECT_ROOT"

LATEST="$(
  find out/ptbr-dialogue-discovery \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -printf '%T@ %p\n' \
  | sort -nr \
  | head -n 1 \
  | cut -d' ' -f2-
)"

if [[ -z "$LATEST" || ! -d "$LATEST" ]]; then
    echo "ERRO: nenhuma sessão de descoberta encontrada."
    exit 1
fi

ADDRESSES="$LATEST/addresses.txt"
REPORT="$LATEST/dialogues-report.txt"

if [[ ! -s "$ADDRESSES" ]]; then
    echo "ERRO: nenhuma fala encontrada em:"
    echo "  $ADDRESSES"
    exit 2
fi

{
    echo "STAR FOX ENHANCED — PT-BR DIALOGUE REPORT"
    echo
    echo "Sessão:"
    echo "  $LATEST"
    echo
    echo "============================================================"

    while IFS= read -r ADDRESS
    do
        [[ -z "$ADDRESS" ]] && continue

        echo
        "$BUILD_DIR/starfox_dialogue_probe" \
            upstream-ultrastarfox/SF.SFC \
            "$ADDRESS"

        echo
        echo "============================================================"

    done < "$ADDRESSES"

} | tee "$REPORT"

echo
echo "Relatório gerado:"
echo "  $REPORT"
