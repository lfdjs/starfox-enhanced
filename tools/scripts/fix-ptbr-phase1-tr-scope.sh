#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-phase1-fix-reports/$STAMP"
REPORT="$REPORT_DIR/report-share.txt"
LOG="$REPORT_DIR/full.log"

mkdir -p "$REPORT_DIR"

cd "$PROJECT_ROOT"

exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo "STAR FOX ENHANCED — CORRECAO PT-BR FASE 01"
echo "============================================================"
echo
echo "Arquivo:"
echo "  $SOURCE"
echo

cp -a \
  "$SOURCE" \
  "$REPORT_DIR/starfox_pc.cpp.before"

export SOURCE

python3 <<'PY'
from pathlib import Path
import os

path = Path(os.environ["SOURCE"])
text = path.read_text(encoding="utf-8")

helper = '''                const auto tr = [&game](starfox::localization::TextId id) {
                    return starfox::localization::text(game.language(), id);
                };

'''

count = text.count(helper)

print(f"Ocorrencias atuais do helper tr(): {count}")

# Remove qualquer insercao anterior em escopo incorreto.
text = text.replace(helper, "")

anchor = '''            if (game.flow_state()
                == starfox::simulation::GameFlowState::pregame_menu) {
                framebuffer.clear(0U);
'''

replacement = '''            if (game.flow_state()
                == starfox::simulation::GameFlowState::pregame_menu) {
                framebuffer.clear(0U);

                const auto tr = [&game](starfox::localization::TextId id) {
                    return starfox::localization::text(game.language(), id);
                };
'''

if replacement in text:
    print("Helper tr() ja esta no escopo correto.")
elif anchor not in text:
    raise RuntimeError(
        "Nao encontrei o inicio do bloco de renderizacao do pre-game menu."
    )
else:
    text = text.replace(anchor, replacement, 1)
    print("Helper tr() movido para o escopo correto do pre-game menu.")

path.write_text(text, encoding="utf-8")

# Validacoes simples.
updated = path.read_text(encoding="utf-8")

helper_count = updated.count(
    'const auto tr = [&game](starfox::localization::TextId id)'
)

if helper_count != 1:
    raise RuntimeError(
        f"Esperava exatamente 1 helper tr(), encontrei {helper_count}."
    )

if 'draw_centred(tr(TextId::options_title)' not in updated:
    raise RuntimeError("Menu OPTIONS traduzido nao encontrado.")

if 'draw_centred(tr(TextId::pregame_setup)' not in updated:
    raise RuntimeError("Menu PRE-GAME traduzido nao encontrado.")

print()
print("Validacao estrutural: OK")
PY

echo
echo "============================================================"
echo "DIFF CHECK"
echo "============================================================"
echo

git diff --check

echo
echo "Trecho do menu:"
echo

grep -n -A18 -B5 \
  'const auto tr = \[&game\]' \
  src/app/starfox_pc.cpp \
  || true

echo
echo "============================================================"
echo "BUILD INCREMENTAL"
echo "============================================================"
echo

cmake \
  --build "$BUILD_DIR" \
  -j"$(nproc)"

echo
echo "============================================================"
echo "CTEST"
echo "============================================================"
echo

ctest \
  --test-dir "$BUILD_DIR" \
  --output-on-failure

echo
echo "============================================================"
echo "SMOKE ORIGINAL"
echo "============================================================"
echo

env \
  SDL_VIDEODRIVER=dummy \
  SDL_AUDIODRIVER=dummy \
  STARFOX_TEST_EXPERIENCE=ORIGINAL \
  STARFOX_TEST_FRAMES=6 \
  STARFOX_TEST_UNPACED=1 \
  "$BUILD_DIR/starfox_pc" \
  upstream-ultrastarfox/SF.SFC \
  upstream-ultrastarfox/SYMBOLS.TXT \
  LEVEL1_1

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"
echo
echo "Correcao concluida."
echo
echo "Executavel:"
echo "  $BUILD_DIR/starfox_pc"
echo

{
    echo "STAR FOX ENHANCED — PT-BR FASE 01 — REPARO"
    echo
    echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo "Projeto: $PROJECT_ROOT"
    echo
    echo "GIT STATUS"
    echo "------------------------------------------------------------"
    git status --short
    echo
    echo "DIFF STAT"
    echo "------------------------------------------------------------"
    git diff --stat
    echo
    echo "ULTIMAS 160 LINHAS"
    echo "------------------------------------------------------------"
    tail -n 160 "$LOG"
} > "$REPORT"

echo
echo "Relatorio:"
echo "  $REPORT"
