#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-hud-phase2b-reports/$STAMP"
BACKUP_DIR="$REPORT_DIR/backup"
LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"

mkdir -p "$BACKUP_DIR"

cd "$PROJECT_ROOT"

exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo "STAR FOX ENHANCED — HUD PT-BR FASE 02B"
echo "SHIELD -> ESCUDO"
echo "============================================================"

FILES=(
    include/starfox/localization/language.hpp
    src/localization/language.cpp
    tests/localization_tests.cpp
    include/starfox/render/sprite_renderer.hpp
    src/render/sprite_renderer.cpp
    src/app/starfox_pc.cpp
)

for file in "${FILES[@]}"
do
    if [[ ! -s "$file" ]]; then
        echo "ERRO: arquivo ausente:"
        echo "  $file"
        exit 10
    fi

    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"

    echo "BACKUP  $file"
done

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])


def patch(rel, old, new, description):
    path = root / rel
    text = path.read_text(encoding="utf-8")

    if new in text:
        print(f"JA OK   {description}")
        return

    if old not in text:
        raise RuntimeError(
            f"Trecho não encontrado em {rel}: {description}"
        )

    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")

    print(f"PATCH   {description}")


# ============================================================
# 1. TextId HUD SHIELD
# ============================================================

patch(
    "include/starfox/localization/language.hpp",
    '''    hud_enemy,

    count,
''',
    '''    hud_enemy,
    hud_shield,

    count,
''',
    "TextId hud_shield"
)

patch(
    "src/localization/language.cpp",
    '''    case TextId::hud_enemy:
        return pt ? "INIMIGO" : "ENEMY";

    case TextId::count:
''',
    '''    case TextId::hud_enemy:
        return pt ? "INIMIGO" : "ENEMY";

    case TextId::hud_shield:
        return pt ? "ESCUDO" : "SHIELD";

    case TextId::count:
''',
    "SHIELD -> ESCUDO"
)


# ============================================================
# 2. Teste de localização
# ============================================================

path = root / "tests/localization_tests.cpp"
text = path.read_text(encoding="utf-8")

marker = '"PT-BR HUD ESCUDO translation is wrong"'

if marker not in text:
    anchor = '''    std::cout << "localization UTF-8 tests passed\\n";
'''

    addition = '''    require(
        text(Language::portuguese_br, TextId::hud_shield)
            == "ESCUDO",
        "PT-BR HUD ESCUDO translation is wrong");

    require(
        text(Language::english, TextId::hud_shield)
            == "SHIELD",
        "English HUD SHIELD translation changed");

    std::cout << "localization UTF-8 tests passed\\n";
'''

    if anchor not in text:
        raise RuntimeError(
            "Ponto dos localization_tests não encontrado"
        )

    text = text.replace(anchor, addition, 1)
    path.write_text(text, encoding="utf-8")

    print("PATCH   teste ESCUDO")
else:
    print("JA OK   teste ESCUDO")


# ============================================================
# 3. API SpriteRenderer
# ============================================================

patch(
    "include/starfox/render/sprite_renderer.hpp",
    '''        const HudLayout* hud_layout = nullptr,
        bool suppress_configurable_hud = false) const noexcept;
''',
    '''        const HudLayout* hud_layout = nullptr,
        bool suppress_configurable_hud = false,
        bool suppress_original_shield_label = false) const noexcept;
''',
    "flag para ocultar somente SHIELD original"
)

patch(
    "src/render/sprite_renderer.cpp",
    '''    const HudLayout* hud_layout,
    bool suppress_configurable_hud) const noexcept {
''',
    '''    const HudLayout* hud_layout,
    bool suppress_configurable_hud,
    bool suppress_original_shield_label) const noexcept {
''',
    "implementação da nova flag"
)


# ============================================================
# 4. Ocultar APENAS tiles 0xCB-0xCE
# ============================================================

path = root / "src/render/sprite_renderer.cpp"
text = path.read_text(encoding="utf-8")

suppression = '''        // Retail SHIELD is encoded as four 8x8 OAM tiles at $CB-$CE.
        // PT-BR replaces only those source text tiles. Keep the shield meter,
        // life counter, bomb icons and every other HUD sprite untouched.
        if (suppress_original_shield_label
            && element
            && *element == HudElement::shield
            && tile >= 0xCBU
            && tile <= 0xCEU) {
            continue;
        }

'''

if suppression not in text:
    anchor = '''        if (suppress_configurable_hud && element) continue;
'''

    if anchor not in text:
        raise RuntimeError(
            "Classificação HudElement não encontrada"
        )

    text = text.replace(
        anchor,
        suppression + anchor,
        1
    )

    path.write_text(text, encoding="utf-8")

    print("PATCH   supressão seletiva tiles CB-CE")
else:
    print("JA OK   supressão seletiva tiles CB-CE")


# ============================================================
# 5. Frontend: ativar apenas em PT-BR
# ============================================================

path = root / "src/app/starfox_pc.cpp"
text = path.read_text(encoding="utf-8")

old_call = '''                        &active_hud_layout,
                        suppress_configurable_hud && gameplay_hud);
'''

new_call = '''                        &active_hud_layout,
                        suppress_configurable_hud && gameplay_hud,
                        game.language()
                            == starfox::localization::Language::portuguese_br);
'''

if new_call in text:
    print("JA OK   SpriteRenderer recebe idioma PT-BR")

elif old_call not in text:
    raise RuntimeError(
        "Chamada principal SpriteRenderer::draw_objects não encontrada"
    )

else:
    text = text.replace(old_call, new_call, 1)
    print("PATCH   SpriteRenderer recebe idioma PT-BR")


# ============================================================
# 6. Desenhar ESCUDO no mesmo grupo de layout
# ============================================================

label_block = '''                if (!suppress_configurable_hud
                    && game.language()
                        == starfox::localization::Language::portuguese_br) {

                    const auto shield_label =
                        starfox::localization::text(
                            game.language(),
                            starfox::localization::TextId::hud_shield);

                    const auto shield_offset =
                        active_hud_layout[
                            starfox::render::HudElement::shield];

                    // Original OAM tiles occupy x=24..55, centred at x=40.
                    // Centre ESCUDO on that same anchor so custom HUD layout
                    // offsets and widescreen edge anchoring remain coherent.
                    const auto shield_label_x =
                        40
                        - text_renderer.measure_utf8(
                            shield_label) / 2
                        + shield_offset.x;

                    const auto shield_label_y =
                        181
                        + shield_offset.y;

                    text_renderer.draw_utf8(
                        shield_label,
                        shield_label_x,
                        shield_label_y,
                        framebuffer,
                        14U);
                }
'''

if label_block in text:
    print("JA OK   label host ESCUDO")

else:
    anchor = '''                }
            }
            const auto comms_offset = active_hud_layout[
'''

    if anchor not in text:
        raise RuntimeError(
            "Fim do bloco gameplay_hud não encontrado"
        )

    replacement = '''                }

''' + label_block + '''            }
            const auto comms_offset = active_hud_layout[
'''

    text = text.replace(anchor, replacement, 1)

    print("PATCH   label host ESCUDO")


path.write_text(text, encoding="utf-8")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

files = [
    "include/starfox/localization/language.hpp",
    "src/localization/language.cpp",
    "include/starfox/render/sprite_renderer.hpp",
    "src/render/sprite_renderer.cpp",
    "src/app/starfox_pc.cpp",
]

for filename in files:
    Path(filename).read_text(encoding="utf-8")
    print("UTF8 OK ", filename)
PY

git diff --check

echo
echo "Tiles que serão substituídos:"
echo
echo "  0xCB"
echo "  0xCC"
echo "  0xCD"
echo "  0xCE"
echo
echo "Tiles preservados:"
echo
echo "  0xBC x3  -> ícones de bomba"
echo "  0xBD     -> grupo de vidas"
echo "  0xE2/E3  -> contador de vidas"

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
echo "SMOKE ENGLISH"
echo "============================================================"

env \
    SDL_VIDEODRIVER=dummy \
    SDL_AUDIODRIVER=dummy \
    STARFOX_TEST_EXPERIENCE=ORIGINAL \
    STARFOX_TEST_LANGUAGE=ENGLISH \
    STARFOX_TEST_FRAMES=12 \
    STARFOX_TEST_UNPACED=1 \
    "$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    LEVEL1_1

echo
echo "============================================================"
echo "SMOKE PT-BR"
echo "============================================================"

env \
    SDL_VIDEODRIVER=dummy \
    SDL_AUDIODRIVER=dummy \
    STARFOX_TEST_EXPERIENCE=ORIGINAL \
    STARFOX_TEST_LANGUAGE=PT_BR \
    STARFOX_TEST_FRAMES=12 \
    STARFOX_TEST_UNPACED=1 \
    "$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    LEVEL1_1

{
    echo "STAR FOX ENHANCED — HUD PT-BR FASE 02B"
    echo
    echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo
    echo "MAPEAMENTO CONFIRMADO"
    echo "  SHIELD object 6 tile 0xCB"
    echo "  SHIELD object 7 tile 0xCC"
    echo "  SHIELD object 8 tile 0xCD"
    echo "  SHIELD object 9 tile 0xCE"
    echo
    echo "PRESERVADOS"
    echo "  BOMB object 0 tile 0xBC"
    echo "  BOMB object 1 tile 0xBC"
    echo "  BOMB object 2 tile 0xBC"
    echo
    echo "TRADUÇÃO"
    echo "  SHIELD -> ESCUDO"
    echo
    echo "GIT STATUS"
    git status --short
    echo
    echo "DIFF STAT"
    git diff --stat
    echo
    echo "ULTIMAS 160 LINHAS"
    tail -n 160 "$LOG"
} > "$REPORT"

echo
echo "============================================================"
echo "HUD PT-BR FASE 02B CONCLUÍDA"
echo "============================================================"
echo
echo "Executável:"
echo "  $BUILD_DIR/starfox_pc"
echo
echo "Relatório:"
echo "  $REPORT"
