#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"

OUT="$PROJECT_ROOT/out/ptbr-hud-discovery/$STAMP"

mkdir -p "$OUT"

FULL_LOG="$OUT/runtime.log"
HUD_LOG="$OUT/hud-oam.txt"
SUMMARY="$OUT/hud-summary.txt"

echo "============================================================"
echo "STAR FOX ENHANCED — HUD OAM DISCOVERY"
echo "============================================================"
echo
echo "Durante esta execução:"
echo
echo "  1. Entre no jogo"
echo "  2. Jogue normalmente"
echo "  3. Observe ESCUDO / BOOST / BOMB"
echo "  4. Se possível, chegue ao chefe de Corneria"
echo "  5. Feche normalmente o jogo"
echo
echo "Log:"
echo "  $FULL_LOG"
echo

set +e

STARFOX_LOG_HUD_OAM=1 \
STARFOX_TEST_LANGUAGE=PT_BR \
"$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    BOOT \
    2> >(tee "$FULL_LOG" >&2)

GAME_RC=$?

set -e

grep '^PTBR_HUD_OAM' \
    "$FULL_LOG" \
    | sort -u \
    > "$HUD_LOG" \
    || true

{
    echo "STAR FOX ENHANCED — HUD OAM SUMMARY"
    echo
    echo "Sessão:"
    echo "  $OUT"
    echo
    echo "Código do jogo:"
    echo "  $GAME_RC"
    echo

    for GROUP in \
        LIVES \
        SHIELD \
        BOMBS_BOOST \
        COMMS \
        BOSS_HEALTH
    do
        echo "============================================================"
        echo "$GROUP"
        echo "============================================================"

        grep "group=$GROUP " \
            "$HUD_LOG" \
            || echo "(nenhuma entrada)"

        echo
    done

} > "$SUMMARY"

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"
echo
echo "Entradas OAM distintas:"
echo "  $(grep -c '^PTBR_HUD_OAM' "$HUD_LOG" || true)"
echo
echo "Relatório:"
echo "  $SUMMARY"
echo
cat "$SUMMARY"

exit 0
