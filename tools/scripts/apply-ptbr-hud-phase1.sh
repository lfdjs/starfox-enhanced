#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-hud-phase1-reports/$STAMP"
BACKUP_DIR="$REPORT_DIR/backup"
LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"

mkdir -p "$BACKUP_DIR"

cd "$PROJECT_ROOT"

exec > >(tee -a "$LOG") 2>&1

echo "============================================================"
echo "STAR FOX ENHANCED — HUD PT-BR FASE 01"
echo "============================================================"

for file in \
    include/starfox/localization/language.hpp \
    src/localization/language.cpp \
    tests/localization_tests.cpp \
    src/app/starfox_pc.cpp
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
# TextId
# ============================================================

patch(
    "include/starfox/localization/language.hpp",
    '''    remap_done,

    count,
''',
    '''    remap_done,

    hud_score,
    hud_total,
    hud_team,
    hud_down,
    hud_pause,
    hud_enemy,

    count,
''',
    "novos TextId da HUD"
)

# ============================================================
# Traduções
# ============================================================

patch(
    "src/localization/language.cpp",
    '''    case TextId::remap_done:
        return pt
            ? "B/START/ESC  CONCLUIR"
            : "B/START/ESC  DONE";

    case TextId::count:
''',
    '''    case TextId::remap_done:
        return pt
            ? "B/START/ESC  CONCLUIR"
            : "B/START/ESC  DONE";

    case TextId::hud_score:
        return pt ? "PONTOS" : "SCORE";

    case TextId::hud_total:
        return pt ? "TOTAL" : "TOTAL SCORE";

    case TextId::hud_team:
        return pt ? "EQUIPE" : "TEAM";

    case TextId::hud_down:
        return pt ? "FORA" : "DOWN";

    case TextId::hud_pause:
        return pt ? "PAUSA" : "PAUSE";

    case TextId::hud_enemy:
        return pt ? "INIMIGO" : "ENEMY";

    case TextId::count:
''',
    "dicionário da HUD"
)

# ============================================================
# Testes
# ============================================================

path = root / "tests/localization_tests.cpp"
text = path.read_text(encoding="utf-8")

if '"PT-BR HUD PAUSA translation is wrong"' not in text:
    anchor = '''    std::cout << "localization UTF-8 tests passed\\n";
'''

    addition = '''    require(
        text(Language::portuguese_br, TextId::hud_score)
            == "PONTOS",
        "PT-BR HUD PONTOS translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_team)
            == "EQUIPE",
        "PT-BR HUD EQUIPE translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_pause)
            == "PAUSA",
        "PT-BR HUD PAUSA translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_enemy)
            == "INIMIGO",
        "PT-BR HUD INIMIGO translation is wrong");

    std::cout << "localization UTF-8 tests passed\\n";
'''

    if anchor not in text:
        raise RuntimeError(
            "Ponto de inserção dos localization_tests não encontrado"
        )

    text = text.replace(anchor, addition, 1)

    path.write_text(text, encoding="utf-8")

    print("PATCH   testes de HUD")
else:
    print("JA OK   testes de HUD")


# ============================================================
# starfox_pc.cpp
# ============================================================

path = root / "src/app/starfox_pc.cpp"
text = path.read_text(encoding="utf-8")


def replace_pc(old, new, description):
    global text

    if new in text:
        print(f"JA OK   {description}")
        return

    if old not in text:
        raise RuntimeError(
            "Trecho não encontrado em starfox_pc.cpp: "
            + description
        )

    text = text.replace(old, new, 1)

    print("PATCH   " + description)


# ------------------------------------------------------------
# SCORE / TOTAL / TEAM
# ------------------------------------------------------------

replace_pc(
    '''                text_renderer.draw_game_text(
                    score_text, 16, 24, superfx_ui);
                text_renderer.draw_game_text(
                    total_score_text, 16, 40, superfx_ui);
                text_renderer.draw_game_text(
                    team_text, 48, 69, superfx_ui);
''',
    '''                if (game.language()
                        == starfox::localization::Language::portuguese_br) {

                    text_renderer.draw_utf8(
                        starfox::localization::text(
                            game.language(),
                            starfox::localization::TextId::hud_score),
                        16,
                        24,
                        superfx_ui,
                        static_cast<std::uint8_t>(
                            rom.read8(score_text) & 0x0fU));

                    text_renderer.draw_utf8(
                        starfox::localization::text(
                            game.language(),
                            starfox::localization::TextId::hud_total),
                        16,
                        40,
                        superfx_ui,
                        static_cast<std::uint8_t>(
                            rom.read8(total_score_text) & 0x0fU));

                    text_renderer.draw_utf8(
                        starfox::localization::text(
                            game.language(),
                            starfox::localization::TextId::hud_team),
                        48,
                        69,
                        superfx_ui,
                        static_cast<std::uint8_t>(
                            rom.read8(team_text) & 0x0fU));

                } else {
                    text_renderer.draw_game_text(
                        score_text, 16, 24, superfx_ui);

                    text_renderer.draw_game_text(
                        total_score_text, 16, 40, superfx_ui);

                    text_renderer.draw_game_text(
                        team_text, 48, 69, superfx_ui);
                }
''',
    "PONTOS / TOTAL / EQUIPE"
)

# ------------------------------------------------------------
# DOWN
# ------------------------------------------------------------

replace_pc(
    '''                        text_renderer.draw_game_text(teammate_down_text,
                            down_x[teammate], 151, superfx_ui);
''',
    '''                        if (game.language()
                                == starfox::localization::Language::portuguese_br) {

                            text_renderer.draw_utf8(
                                starfox::localization::text(
                                    game.language(),
                                    starfox::localization::TextId::hud_down),
                                down_x[teammate],
                                151,
                                superfx_ui,
                                static_cast<std::uint8_t>(
                                    rom.read8(teammate_down_text) & 0x0fU));

                        } else {
                            text_renderer.draw_game_text(
                                teammate_down_text,
                                down_x[teammate],
                                151,
                                superfx_ui);
                        }
''',
    "DOWN -> FORA"
)

# ------------------------------------------------------------
# PAUSE
# ------------------------------------------------------------

replace_pc(
    '''            if (game.paused()) {
                text_renderer.draw_game_text(
                    pause_text, 90, 90, superfx_ui);
            }
''',
    '''            if (game.paused()) {
                if (game.language()
                        == starfox::localization::Language::portuguese_br) {

                    text_renderer.draw_utf8(
                        starfox::localization::text(
                            game.language(),
                            starfox::localization::TextId::hud_pause),
                        90,
                        90,
                        superfx_ui,
                        static_cast<std::uint8_t>(
                            rom.read8(pause_text) & 0x0fU));

                } else {
                    text_renderer.draw_game_text(
                        pause_text,
                        90,
                        90,
                        superfx_ui);
                }
            }
''',
    "PAUSE -> PAUSA"
)

# ------------------------------------------------------------
# ENEMY do editor de HUD
# ------------------------------------------------------------

old_enemy = '''                    constexpr std::string_view enemy_label{"ENEMY"};
                    text_renderer.draw_ascii(enemy_label,
                        boss_x - text_renderer.measure_ascii(enemy_label) - 4,
                        1 + boss_offset.y, superfx_hud, 14U);
'''

new_enemy = '''                    const auto enemy_label =
                        starfox::localization::text(
                            game.language(),
                            starfox::localization::TextId::hud_enemy);

                    text_renderer.draw_utf8(
                        enemy_label,
                        boss_x
                            - text_renderer.measure_utf8(enemy_label)
                            - 4,
                        1 + boss_offset.y,
                        superfx_hud,
                        14U);
'''

replace_pc(
    old_enemy,
    new_enemy,
    "ENEMY -> INIMIGO no preview do HUD"
)

path.write_text(text, encoding="utf-8")

print()
print("HUD PT-BR Fase 01 aplicada.")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

for filename in (
    "include/starfox/localization/language.hpp",
    "src/localization/language.cpp",
    "tests/localization_tests.cpp",
    "src/app/starfox_pc.cpp",
):
    Path(filename).read_text(encoding="utf-8")
    print("UTF8 OK ", filename)
PY

git diff --check

echo
echo "============================================================"
echo "BUILD"
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
    BOOT

{
    echo "STAR FOX ENHANCED — HUD PT-BR FASE 01"
    echo
    echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo
    echo "Traduções:"
    echo "  SCORE       -> PONTOS"
    echo "  TOTAL SCORE -> TOTAL"
    echo "  TEAM        -> EQUIPE"
    echo "  DOWN        -> FORA"
    echo "  PAUSE       -> PAUSA"
    echo "  ENEMY       -> INIMIGO"
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
echo "CONCLUÍDO"
echo "============================================================"
echo
echo "Relatório:"
echo "  $REPORT"
