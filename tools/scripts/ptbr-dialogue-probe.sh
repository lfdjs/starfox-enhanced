#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

cd "$PROJECT_ROOT"

if [[ "$#" -ne 1 ]]; then
    echo "Uso:"
    echo
    echo "  ./tools/scripts/ptbr-dialogue-probe.sh 0xENDERECO"
    echo

    exit 2
fi

ADDRESS="$1"

ROM="$PROJECT_ROOT/upstream-ultrastarfox/SF.SFC"
PROBE="$BUILD_DIR/starfox_dialogue_probe"

if [[ ! -x "$PROBE" ]]; then
    echo "ERRO: starfox_dialogue_probe ainda não foi compilado."
    exit 10
fi

if [[ ! -s "$ROM" ]]; then
    echo "ERRO: SF.SFC ausente."
    exit 11
fi

exec \
    "$PROBE" \
    "$ROM" \
    "$ADDRESS"
