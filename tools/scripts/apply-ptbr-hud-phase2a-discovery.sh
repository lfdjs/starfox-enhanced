#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"
SOURCE="$PROJECT_ROOT/src/render/sprite_renderer.cpp"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-hud-phase2a-reports/$STAMP"
BACKUP_DIR="$REPORT_DIR/backup"
LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"

mkdir -p "$BACKUP_DIR"

cd "$PROJECT_ROOT"

exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo "STAR FOX ENHANCED — HUD PT-BR FASE 02A"
echo "MAPEAMENTO DOS SPRITES OAM"
echo "============================================================"

if [[ ! -s "$SOURCE" ]]; then
    echo "ERRO: sprite_renderer.cpp ausente."
    exit 10
fi

cp -a \
    "$SOURCE" \
    "$BACKUP_DIR/sprite_renderer.cpp"

export SOURCE

python3 <<'PY'
from pathlib import Path
import os

path = Path(os.environ["SOURCE"])
text = path.read_text(encoding="utf-8")

# ------------------------------------------------------------
# Includes de diagnóstico
# ------------------------------------------------------------

includes = {
    "#include <cstdlib>\n": "#include <cstdlib>\n",
    "#include <iostream>\n": "#include <iostream>\n",
    "#include <string>\n": "#include <string>\n",
    "#include <unordered_set>\n": "#include <unordered_set>\n",
}

anchor = "#include <cstdint>\n"

if anchor not in text:
    raise RuntimeError("include <cstdint> não encontrado.")

to_add = ""

for include in includes:
    if include not in text:
        to_add += include

if to_add:
    text = text.replace(
        anchor,
        anchor + to_add,
        1
    )

    print("PATCH   includes de diagnóstico")
else:
    print("JA OK   includes de diagnóstico")


# ------------------------------------------------------------
# Nome textual de HudElement
# ------------------------------------------------------------

helper = r'''
const char* hud_element_debug_name(
    HudElement element) noexcept {

    switch (element) {
    case HudElement::lives:
        return "LIVES";

    case HudElement::shield:
        return "SHIELD";

    case HudElement::bombs_boost:
        return "BOMBS_BOOST";

    case HudElement::comms:
        return "COMMS";

    case HudElement::boss_health:
        return "BOSS_HEALTH";

    case HudElement::count:
    default:
        return "UNKNOWN";
    }
}

'''

if "hud_element_debug_name(" not in text:
    marker = "} // namespace\n\nvoid SpriteRenderer::draw_objects("

    if marker not in text:
        raise RuntimeError(
            "fim do namespace anônimo não encontrado."
        )

    text = text.replace(
        marker,
        helper + marker,
        1
    )

    print("PATCH   hud_element_debug_name")
else:
    print("JA OK   hud_element_debug_name")


# ------------------------------------------------------------
# Log das entradas OAM classificadas como HUD
# ------------------------------------------------------------

old = '''        if (priority && object_priority != *priority) continue;
        const auto flip_x = (ppu.oam[low + 3U] & 0x40U) != 0U;
'''

new = '''        if (priority && object_priority != *priority) continue;

        if (std::getenv("STARFOX_LOG_HUD_OAM") != nullptr
            && hud_layout != nullptr
            && element.has_value()) {

            static std::unordered_set<std::string> logged_entries;

            const auto key =
                std::to_string(static_cast<unsigned>(*element))
                + ":"
                + std::to_string(object)
                + ":"
                + std::to_string(x)
                + ":"
                + std::to_string(static_cast<unsigned>(y_byte))
                + ":"
                + std::to_string(static_cast<unsigned>(tile))
                + ":"
                + std::to_string(static_cast<unsigned>(palette))
                + ":"
                + std::to_string(static_cast<unsigned>(object_priority))
                + ":"
                + std::to_string(static_cast<unsigned>(size));

            if (logged_entries.insert(key).second) {
                std::cerr
                    << "PTBR_HUD_OAM"
                    << " group="
                    << hud_element_debug_name(*element)
                    << " object="
                    << object
                    << " x="
                    << x
                    << " y="
                    << static_cast<unsigned>(y_byte)
                    << " tile=0x"
                    << std::hex
                    << std::uppercase
                    << static_cast<unsigned>(tile)
                    << std::nouppercase
                    << std::dec
                    << " palette="
                    << static_cast<unsigned>(palette)
                    << " priority="
                    << static_cast<unsigned>(object_priority)
                    << " size="
                    << size
                    << " raw="
                    << static_cast<unsigned>(ppu.oam[low])
                    << ","
                    << static_cast<unsigned>(ppu.oam[low + 1U])
                    << ","
                    << static_cast<unsigned>(ppu.oam[low + 2U])
                    << ","
                    << static_cast<unsigned>(ppu.oam[low + 3U])
                    << '\\n';
            }
        }

        const auto flip_x = (ppu.oam[low + 3U] & 0x40U) != 0U;
'''

if new in text:
    print("JA OK   logger OAM")

elif old not in text:
    raise RuntimeError(
        "ponto de inserção do logger OAM não encontrado."
    )

else:
    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   logger OAM")

path.write_text(
    text,
    encoding="utf-8"
)
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

grep -n \
    -A8 \
    -B4 \
    'PTBR_HUD_OAM' \
    src/render/sprite_renderer.cpp \
    || true

echo
echo "============================================================"
echo "BUILD INCREMENTAL"
echo "============================================================"

cmake \
    --build "$BUILD_DIR" \
    -j"$(nproc)"

echo
echo "============================================================"
echo "CTEST"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure

echo
echo "============================================================"
echo "CRIANDO SCRIPT DE DESCOBERTA"
echo "============================================================"

touch tools/scripts/ptbr-hud-discovery.sh

cat > tools/scripts/ptbr-hud-discovery.sh <<'DISCOVERY_EOF'
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
DISCOVERY_EOF

chmod +x \
    tools/scripts/ptbr-hud-discovery.sh

bash -n \
    tools/scripts/ptbr-hud-discovery.sh

{
    echo "STAR FOX ENHANCED — HUD PT-BR FASE 02A"
    echo
    echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo
    echo "Instrumentação OAM instalada."
    echo
    echo "Próximo comando:"
    echo "  ./tools/scripts/ptbr-hud-discovery.sh"
    echo
    echo "GIT STATUS"
    git status --short
    echo
    echo "DIFF STAT"
    git diff --stat
    echo
    echo "ULTIMAS 120 LINHAS"
    tail -n 120 "$LOG"
} > "$REPORT"

echo
echo "============================================================"
echo "FASE 02A CONCLUÍDA"
echo "============================================================"
echo
echo "Agora execute:"
echo
echo "  ./tools/scripts/ptbr-hud-discovery.sh"
echo
echo "Relatório de instalação:"
echo "  $REPORT"
