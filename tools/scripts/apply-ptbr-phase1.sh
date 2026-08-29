#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-phase1-reports/$STAMP"

FULL_LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"
BACKUP_DIR="$REPORT_DIR/backup"

mkdir -p "$REPORT_DIR" "$BACKUP_DIR"

cd "$PROJECT_ROOT"

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

finish_report() {
    {
        echo "STAR FOX ENHANCED — PT-BR FASE 01"
        echo
        echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
        echo "Projeto: $PROJECT_ROOT"
        echo "Build:   $BUILD_DIR"
        echo "Código:  $FINAL_RC"
        echo

        echo "============================================================"
        echo "GIT STATUS"
        echo "============================================================"

        git status --short || true

        echo
        echo "============================================================"
        echo "GIT DIFF --STAT"
        echo "============================================================"

        git diff --stat || true

        echo
        echo "============================================================"
        echo "ARQUIVOS DE LOCALIZACAO"
        echo "============================================================"

        for file in \
            include/starfox/localization/language.hpp \
            src/localization/language.cpp \
            tests/localization_tests.cpp
        do
            if [[ -s "$file" ]]; then
                echo "OK      $file"
            else
                echo "AUSENTE $file"
            fi
        done

        echo
        echo "============================================================"
        echo "ULTIMAS 160 LINHAS"
        echo "============================================================"

        tail -n 160 "$FULL_LOG" || true

    } > "$REPORT"

    echo
    line
    echo "RELATORIO"
    line
    echo
    echo "$REPORT"
}

on_exit() {
    local rc=$?

    trap - EXIT

    if [[ "$FINAL_RC" -eq 0 && "$rc" -ne 0 ]]; then
        FINAL_RC="$rc"
    fi

    finish_report

    exit "$FINAL_RC"
}

trap on_exit EXIT

section "STAR FOX ENHANCED — LOCALIZACAO PT-BR FASE 01"

echo "Projeto:"
echo "  $PROJECT_ROOT"

# ============================================================
# ETAPA 1 — preflight
# ============================================================

section "ETAPA 1 — PREFLIGHT"

for file in \
    CMakeLists.txt \
    include/starfox/app/runtime_input.hpp \
    include/starfox/simulation/game_simulation.hpp \
    src/app/runtime_input.cpp \
    src/app/starfox_pc.cpp \
    src/simulation/game_simulation.cpp \
    tests/runtime_input_tests.cpp \
    tests/simulation_tests.cpp
do
    if [[ ! -s "$file" ]]; then
        echo "ERRO: arquivo ausente:"
        echo "$file"

        FINAL_RC=10
        exit "$FINAL_RC"
    fi

    echo "OK      $file"
done

echo
echo "Commit atual:"
git log -1 --oneline

echo
echo "Status:"
git status --short

# ============================================================
# ETAPA 2 — backup
# ============================================================

section "ETAPA 2 — BACKUP"

for file in \
    CMakeLists.txt \
    include/starfox/app/runtime_input.hpp \
    include/starfox/simulation/game_simulation.hpp \
    src/app/runtime_input.cpp \
    src/app/starfox_pc.cpp \
    src/simulation/game_simulation.cpp \
    tests/runtime_input_tests.cpp \
    tests/simulation_tests.cpp
do
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"

    echo "BACKUP  $file"
done

# ============================================================
# ETAPA 3 — aplicar patch
# ============================================================

section "ETAPA 3 — APLICANDO LOCALIZACAO"

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])


def read(rel):
    return (root / rel).read_text(encoding="utf-8")


def write(rel, content):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"WRITE   {rel}")


def replace_once(rel, old, new, description):
    path = root / rel
    text = path.read_text(encoding="utf-8")

    if new in text:
        print(f"JA OK   {rel}: {description}")
        return

    if old not in text:
        raise RuntimeError(
            f"Trecho esperado nao encontrado em {rel}: {description}"
        )

    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")

    print(f"PATCH   {rel}: {description}")


# ============================================================
# Nova infraestrutura de idioma
# ============================================================

write(
    "include/starfox/localization/language.hpp",
    r'''#pragma once

#include <cstdint>
#include <string_view>

namespace starfox::localization {

enum class Language : std::uint8_t {
    english = 0,
    portuguese_br = 1,
};

enum class TextId : std::uint8_t {
    title,
    pregame_setup,
    options_title,

    experience,
    game_pace,
    render_fps,
    display,
    controller,
    options,
    start_game,

    god_mode,
    onscreen_fps,
    crosshair_color,
    language,
    customize_screen,
    back,

    on,
    off,
    open,
    remap,

    change_hint,
    back_hint,
    choose_hint,
    begin_hint,

    unlocked_20_hz,
    original_speed,

    display_4_3,
    display_16_9,
    display_16_10,
    display_21_9,
    display_32_9,

    original_experience,
    starfox_ex_experience,

    count,
};

[[nodiscard]] std::string_view text(
    Language language,
    TextId id) noexcept;

[[nodiscard]] std::string_view language_name(
    Language language) noexcept;

} // namespace starfox::localization
'''
)

write(
    "src/localization/language.cpp",
    r'''#include "starfox/localization/language.hpp"

#include <array>
#include <cstddef>

namespace starfox::localization {
namespace {

constexpr auto kEnglish =
    std::array<std::string_view,
        static_cast<std::size_t>(TextId::count)>{
        "STAR FOX ENHANCED",
        "PRE-GAME SETUP",
        "OPTIONS",

        "EXPERIENCE",
        "GAME PACE",
        "RENDER FPS",
        "DISPLAY",
        "CONTROLLER",
        "OPTIONS",
        "START GAME",

        "GOD MODE",
        "ON-SCREEN FPS",
        "CROSSHAIR COLOR",
        "LANGUAGE",
        "CUSTOMIZE SCREEN",
        "BACK",

        "ON",
        "OFF",
        "A  OPEN",
        "A  REMAP",

        "A/LEFT/RIGHT  CHANGE",
        "B  BACK",
        "D-PAD CHOOSE  A SELECT",
        "START  BEGIN",

        "UNLOCKED 20 HZ",
        "ORIGINAL",

        "4 BY 3 STANDARD",
        "16 BY 9 WIDE",
        "16 BY 10 WIDE",
        "21 BY 9 ULTRA",
        "32 BY 9 SUPER",

        "ORIGINAL",
        "STARFOX EX",
    };

constexpr auto kPortugueseBr =
    std::array<std::string_view,
        static_cast<std::size_t>(TextId::count)>{
        "STAR FOX ENHANCED",
        "CONFIGURACAO",
        "OPCOES",

        "EXPERIENCIA",
        "RITMO DO JOGO",
        "FPS DE RENDER",
        "TELA",
        "CONTROLE",
        "OPCOES",
        "INICIAR JOGO",

        "MODO DEUS",
        "FPS NA TELA",
        "COR DA MIRA",
        "IDIOMA",
        "AJUSTAR TELA",
        "VOLTAR",

        "LIGADO",
        "DESLIGADO",
        "A  ABRIR",
        "A  MAPEAR",

        "A/ESQ/DIR  ALTERA",
        "B  VOLTAR",
        "D-PAD ESCOLHE  A CONFIRMA",
        "START  INICIA",

        "20 HZ LIVRE",
        "ORIGINAL",

        "4 POR 3 PADRAO",
        "16 POR 9 AMPLO",
        "16 POR 10 AMPLO",
        "21 POR 9 ULTRA",
        "32 POR 9 SUPER",

        "ORIGINAL",
        "STARFOX EX",
    };

} // namespace

std::string_view text(
    Language language,
    TextId id) noexcept {

    const auto index = static_cast<std::size_t>(id);

    if (index >= kEnglish.size()) {
        return {};
    }

    if (language == Language::portuguese_br) {
        return kPortugueseBr[index];
    }

    return kEnglish[index];
}

std::string_view language_name(Language language) noexcept {
    return language == Language::portuguese_br
        ? std::string_view{"PORTUGUES BR"}
        : std::string_view{"ENGLISH"};
}

} // namespace starfox::localization
'''
)

write(
    "tests/localization_tests.cpp",
    r'''#include "starfox/localization/language.hpp"

#include <cstdlib>
#include <iostream>
#include <string_view>

namespace {

void require(bool condition, std::string_view message) {
    if (!condition) {
        std::cerr << "localization test failed: "
                  << message << '\n';
        std::exit(1);
    }
}

} // namespace

int main() {
    using starfox::localization::Language;
    using starfox::localization::TextId;
    using starfox::localization::language_name;
    using starfox::localization::text;

    require(
        text(Language::english, TextId::start_game)
            == "START GAME",
        "English START GAME changed");

    require(
        text(Language::portuguese_br, TextId::start_game)
            == "INICIAR JOGO",
        "PT-BR START GAME translation is wrong");

    require(
        text(Language::portuguese_br, TextId::options)
            == "OPCOES",
        "PT-BR OPTIONS translation is wrong");

    require(
        language_name(Language::english)
            == "ENGLISH",
        "English language label is wrong");

    require(
        language_name(Language::portuguese_br)
            == "PORTUGUES BR",
        "PT-BR language label is wrong");

    std::cout << "localization tests passed\n";

    return 0;
}
'''
)

# ============================================================
# CMake
# ============================================================

replace_once(
    "CMakeLists.txt",
    """    src/assets/shape_decoder.cpp
    src/render/background_renderer.cpp
""",
    """    src/assets/shape_decoder.cpp
    src/localization/language.cpp
    src/render/background_renderer.cpp
""",
    "adicionar language.cpp ao starfox_core"
)

replace_once(
    "CMakeLists.txt",
    """    add_executable(starfox_core_tests tests/timing_tests.cpp)
    target_link_libraries(starfox_core_tests PRIVATE starfox_core)
    add_test(NAME starfox_core_tests COMMAND starfox_core_tests)

""",
    """    add_executable(starfox_core_tests tests/timing_tests.cpp)
    target_link_libraries(starfox_core_tests PRIVATE starfox_core)
    add_test(NAME starfox_core_tests COMMAND starfox_core_tests)

    add_executable(starfox_localization_tests tests/localization_tests.cpp)
    target_link_libraries(starfox_localization_tests PRIVATE starfox_core)
    add_test(NAME starfox_localization_tests COMMAND starfox_localization_tests)

""",
    "adicionar testes de localizacao"
)

replace_once(
    "CMakeLists.txt",
    '''                    "SDL_VIDEODRIVER=dummy;SDL_AUDIODRIVER=dummy;STARFOX_TEST_FRAMES=6"
''',
    '''                    "SDL_VIDEODRIVER=dummy;SDL_AUDIODRIVER=dummy;STARFOX_TEST_EXPERIENCE=ORIGINAL;STARFOX_TEST_FRAMES=6"
''',
    "forcar Original no smoke test sem assets EX"
)

# ============================================================
# GameSimulation header
# ============================================================

replace_once(
    "include/starfox/simulation/game_simulation.hpp",
    '''#include "starfox/input/input_latch.hpp"
''',
    '''#include "starfox/input/input_latch.hpp"
#include "starfox/localization/language.hpp"
''',
    "incluir Language"
)

replace_once(
    "include/starfox/simulation/game_simulation.hpp",
    '''    [[nodiscard]] Experience experience() const noexcept { return experience_; }
    void set_experience(Experience experience) noexcept { experience_ = experience; }
''',
    '''    [[nodiscard]] Experience experience() const noexcept { return experience_; }
    void set_experience(Experience experience) noexcept { experience_ = experience; }

    [[nodiscard]] starfox::localization::Language language() const noexcept {
        return language_;
    }

    void set_language(starfox::localization::Language language) noexcept {
        language_ = language;
    }
''',
    "getter/setter de idioma"
)

replace_once(
    "include/starfox/simulation/game_simulation.hpp",
    '''    Experience experience_{Experience::original};
    bool god_mode_{};
''',
    '''    Experience experience_{Experience::original};
    starfox::localization::Language language_{
        starfox::localization::Language::english};
    bool god_mode_{};
''',
    "estado de idioma"
)

# ============================================================
# GameSimulation options
# ============================================================

replace_once(
    "src/simulation/game_simulation.cpp",
    '''    const auto selection_count = pregame_page_ == PregamePage::main
        ? std::uint8_t{7U} : std::uint8_t{5U};
''',
    '''    const auto selection_count = pregame_page_ == PregamePage::main
        ? std::uint8_t{7U} : std::uint8_t{6U};
''',
    "OPTIONS passa de 5 para 6 itens"
)

replace_once(
    "src/simulation/game_simulation.cpp",
    '''        const auto go_back = (input.pressed & starfox::input::b) != 0U
            || (pregame_selection_ == 4U
''',
    '''        const auto go_back = (input.pressed & starfox::input::b) != 0U
            || (pregame_selection_ == 5U
''',
    "BACK passa para indice 5"
)

old_crosshair = '''            crosshair_colour_ = kCrosshairColours[index];
            queue_sound_effect(0x11U);
        }
        result.audio_port_writes = map_.take_apu_port_writes();
'''

new_crosshair = '''            crosshair_colour_ = kCrosshairColours[index];
            queue_sound_effect(0x11U);
        } else if (pregame_selection_ == 3U
                   && (input.pressed & (starfox::input::left
                       | starfox::input::right | starfox::input::select
                       | starfox::input::a)) != 0U) {
            language_ = language_
                    == starfox::localization::Language::english
                ? starfox::localization::Language::portuguese_br
                : starfox::localization::Language::english;
            queue_sound_effect(0x11U);
        }
        result.audio_port_writes = map_.take_apu_port_writes();
'''

replace_once(
    "src/simulation/game_simulation.cpp",
    old_crosshair,
    new_crosshair,
    "seletor EN/PT-BR"
)

# ============================================================
# PregameSettings
# ============================================================

replace_once(
    "include/starfox/app/runtime_input.hpp",
    '''    std::uint8_t experience{};

    [[nodiscard]] bool operator==(const PregameSettings&) const = default;
''',
    '''    std::uint8_t experience{};
    std::uint8_t language{};

    [[nodiscard]] bool operator==(const PregameSettings&) const = default;
''',
    "persistir idioma"
)

replace_once(
    "src/app/runtime_input.cpp",
    '''    if (!(input >> version)
        || (version != "SFE_PREGAME_V1" && version != "SFE_PREGAME_V2")) {
''',
    '''    if (!(input >> version)
        || (version != "SFE_PREGAME_V1"
            && version != "SFE_PREGAME_V2"
            && version != "SFE_PREGAME_V3")) {
''',
    "aceitar pregame V3"
)

replace_once(
    "src/app/runtime_input.cpp",
    '''    std::array<bool, 7> found{};
    found[6] = version == "SFE_PREGAME_V1";
''',
    '''    std::array<bool, 8> found{};
    found[6] = version == "SFE_PREGAME_V1";
    found[7] = version != "SFE_PREGAME_V3";
''',
    "migracao V1/V2 para English"
)

replace_once(
    "src/app/runtime_input.cpp",
    '''        } else if (name == "EXPERIENCE") {
            loaded.experience = static_cast<std::uint8_t>(value);
            found[6] = value >= 0 && value <= 1;
        }
''',
    '''        } else if (name == "EXPERIENCE") {
            loaded.experience = static_cast<std::uint8_t>(value);
            found[6] = value >= 0 && value <= 1;
        } else if (name == "LANGUAGE") {
            loaded.language = static_cast<std::uint8_t>(value);
            found[7] = value >= 0 && value <= 1;
        }
''',
    "ler LANGUAGE"
)

replace_once(
    "src/app/runtime_input.cpp",
    '''        || settings.display_mode > 4U || settings.crosshair_colour > 7U
        || settings.experience > 1U) {
''',
    '''        || settings.display_mode > 4U || settings.crosshair_colour > 7U
        || settings.experience > 1U || settings.language > 1U) {
''',
    "validar LANGUAGE"
)

replace_once(
    "src/app/runtime_input.cpp",
    '''    output << "SFE_PREGAME_V2\\n"
           << "EXPERIENCE " << static_cast<unsigned>(settings.experience) << '\\n'
''',
    '''    output << "SFE_PREGAME_V3\\n"
           << "EXPERIENCE " << static_cast<unsigned>(settings.experience) << '\\n'
           << "LANGUAGE " << static_cast<unsigned>(settings.language) << '\\n'
''',
    "salvar V3 com LANGUAGE"
)

# ============================================================
# starfox_pc
# ============================================================

replace_once(
    "src/app/starfox_pc.cpp",
    '''#include "starfox/input/input_latch.hpp"
''',
    '''#include "starfox/input/input_latch.hpp"
#include "starfox/localization/language.hpp"
''',
    "incluir localizacao no frontend"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                static_cast<std::uint8_t>(game.experience()),
            };
''',
    '''                static_cast<std::uint8_t>(game.experience()),
                static_cast<std::uint8_t>(game.language()),
            };
''',
    "capturar idioma no pregame.cfg"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''            game.set_experience(active_experience);
            if (hud_editor_preview) {
''',
    '''            game.set_experience(active_experience);
            game.set_language(
                static_cast<starfox::localization::Language>(
                    saved_pregame.language));
            if (hud_editor_preview) {
''',
    "restaurar idioma salvo"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                               == starfox::simulation::PregamePage::options
                               && game.pregame_selection() == 3U
''',
    '''                               == starfox::simulation::PregamePage::options
                               && game.pregame_selection() == 4U
''',
    "CUSTOMIZE SCREEN passa para indice 4"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                if (hud_editor.active) {
''',
    '''                const auto tr = [&game](starfox::localization::TextId id) {
                    return starfox::localization::text(game.language(), id);
                };

                if (hud_editor.active) {
''',
    "helper tr() do menu"
)

old_options = '''                    if (game.pregame_page()
                        == starfox::simulation::PregamePage::options) {
                        draw_centred("OPTIONS", 40, 10U);
                        const auto god_value = game.god_mode()
                            ? std::string_view{"ON"} : std::string_view{"OFF"};
                        const auto fps_value = game.show_fps()
                            ? std::string_view{"ON"} : std::string_view{"OFF"};
                        const auto crosshair = crosshair_colour_name(
                            game.crosshair_colour());
                        draw_row("GOD MODE", god_value, 56,
                            game.pregame_selection() == 0U);
                        draw_row("ON-SCREEN FPS", fps_value, 76,
                            game.pregame_selection() == 1U);
                        draw_row("CROSSHAIR COLOR", crosshair, 96,
                            game.pregame_selection() == 2U);
                        draw_row("CUSTOMIZE SCREEN", "A  OPEN", 116,
                            game.pregame_selection() == 3U);
                        draw_row("BACK", "", 146,
                            game.pregame_selection() == 4U);
                        constexpr std::array<std::int32_t, 5> cursor_y{
                            59, 79, 99, 119, 149};
                        draw_cursor(cursor_y[game.pregame_selection()]);
                        draw_centred("A/LEFT/RIGHT  CHANGE", 181, 13U);
                        draw_centred("B  BACK", 191, 13U);
'''

new_options = '''                    if (game.pregame_page()
                        == starfox::simulation::PregamePage::options) {
                        using starfox::localization::TextId;

                        draw_centred(tr(TextId::options_title), 40, 10U);

                        const auto god_value = game.god_mode()
                            ? tr(TextId::on) : tr(TextId::off);

                        const auto fps_value = game.show_fps()
                            ? tr(TextId::on) : tr(TextId::off);

                        const auto crosshair = crosshair_colour_name(
                            game.crosshair_colour());

                        draw_row(tr(TextId::god_mode), god_value, 56,
                            game.pregame_selection() == 0U);

                        draw_row(tr(TextId::onscreen_fps), fps_value, 76,
                            game.pregame_selection() == 1U);

                        draw_row(tr(TextId::crosshair_color), crosshair, 96,
                            game.pregame_selection() == 2U);

                        draw_row(tr(TextId::language),
                            starfox::localization::language_name(
                                game.language()),
                            114,
                            game.pregame_selection() == 3U);

                        draw_row(tr(TextId::customize_screen),
                            tr(TextId::open), 132,
                            game.pregame_selection() == 4U);

                        draw_row(tr(TextId::back), "", 150,
                            game.pregame_selection() == 5U);

                        constexpr std::array<std::int32_t, 6> cursor_y{
                            59, 79, 99, 117, 135, 153};

                        draw_cursor(cursor_y[game.pregame_selection()]);

                        draw_centred(tr(TextId::change_hint), 181, 13U);
                        draw_centred(tr(TextId::back_hint), 191, 13U);
'''

replace_once(
    "src/app/starfox_pc.cpp",
    old_options,
    new_options,
    "traduzir pagina OPTIONS"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                        draw_centred("PRE-GAME SETUP", 46, 10U);
''',
    '''                        using starfox::localization::TextId;

                        draw_centred(tr(TextId::pregame_setup), 46, 10U);
''',
    "traduzir titulo do setup"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                        const auto timing = game.timing_mode()
                            == starfox::simulation::TimingMode::unlocked_20_fps
                            ? std::string_view{"UNLOCKED 20 HZ"}
                            : std::string_view{"ORIGINAL"};
''',
    '''                        const auto timing = game.timing_mode()
                            == starfox::simulation::TimingMode::unlocked_20_fps
                            ? tr(TextId::unlocked_20_hz)
                            : tr(TextId::original_speed);
''',
    "traduzir ritmo"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                        const auto display = [mode = game.display_mode()]()
                            -> std::string_view {
                            switch (mode) {
                            case starfox::simulation::DisplayMode::widescreen_16_9:
                                return "16 BY 9 WIDE";
                            case starfox::simulation::DisplayMode::widescreen_16_10:
                                return "16 BY 10 WIDE";
                            case starfox::simulation::DisplayMode::ultrawide_21_9:
                                return "21 BY 9 ULTRA";
                            case starfox::simulation::DisplayMode::super_ultrawide_32_9:
                                return "32 BY 9 SUPER";
                            case starfox::simulation::DisplayMode::standard_4_3:
                            default:
                                return "4 BY 3 STANDARD";
                            }
                        }();
''',
    '''                        const auto display =
                            [&tr, mode = game.display_mode()]()
                                -> std::string_view {
                            switch (mode) {
                            case starfox::simulation::DisplayMode::widescreen_16_9:
                                return tr(TextId::display_16_9);
                            case starfox::simulation::DisplayMode::widescreen_16_10:
                                return tr(TextId::display_16_10);
                            case starfox::simulation::DisplayMode::ultrawide_21_9:
                                return tr(TextId::display_21_9);
                            case starfox::simulation::DisplayMode::super_ultrawide_32_9:
                                return tr(TextId::display_32_9);
                            case starfox::simulation::DisplayMode::standard_4_3:
                            default:
                                return tr(TextId::display_4_3);
                            }
                        }();
''',
    "traduzir modos de tela"
)

replace_once(
    "src/app/starfox_pc.cpp",
    '''                        const auto experience = game.experience()
                            == starfox::simulation::Experience::original
                            ? std::string_view{"ORIGINAL"}
                            : std::string_view{"STARFOX EX"};
''',
    '''                        const auto experience = game.experience()
                            == starfox::simulation::Experience::original
                            ? tr(TextId::original_experience)
                            : tr(TextId::starfox_ex_experience);
''',
    "traduzir experiencia"
)

replacements = {
    '''                        draw_row("EXPERIENCE", experience, row_y[0],
''':
    '''                        draw_row(tr(TextId::experience), experience, row_y[0],
''',

    '''                        draw_row("GAME PACE", timing, row_y[1],
''':
    '''                        draw_row(tr(TextId::game_pace), timing, row_y[1],
''',

    '''                        draw_row("RENDER FPS", presentation, row_y[2],
''':
    '''                        draw_row(tr(TextId::render_fps), presentation, row_y[2],
''',

    '''                        draw_row("DISPLAY", display, row_y[3],
''':
    '''                        draw_row(tr(TextId::display), display, row_y[3],
''',

    '''                        draw_row("CONTROLLER", "A  REMAP", row_y[4],
''':
    '''                        draw_row(tr(TextId::controller), tr(TextId::remap), row_y[4],
''',

    '''                        draw_row("OPTIONS", "A  OPEN", row_y[5],
''':
    '''                        draw_row(tr(TextId::options), tr(TextId::open), row_y[5],
''',

    '''                        draw_row("START GAME", "", row_y[6],
''':
    '''                        draw_row(tr(TextId::start_game), "", row_y[6],
''',

    '''                        draw_centred("D-PAD CHOOSE   A SELECT", 181, 13U);
''':
    '''                        draw_centred(tr(TextId::choose_hint), 181, 13U);
''',

    '''                        draw_centred("START  BEGIN", 191, 13U);
''':
    '''                        draw_centred(tr(TextId::begin_hint), 191, 13U);
''',
}

for old, new in replacements.items():
    replace_once(
        "src/app/starfox_pc.cpp",
        old,
        new,
        "traducao de string do setup"
    )

# ============================================================
# Testes de persistencia
# ============================================================

replace_once(
    "tests/runtime_input_tests.cpp",
    '''    const starfox::app::PregameSettings saved_pregame{
        1U, 90U, 3U, true, true, 5U, 1U};
''',
    '''    const starfox::app::PregameSettings saved_pregame{
        1U, 90U, 3U, true, true, 5U, 1U, 1U};
''',
    "round-trip inclui PT-BR"
)

# ============================================================
# Testes GameSimulation
# ============================================================

replace_once(
    "tests/simulation_tests.cpp",
    '''                    && boot_game.experience()
                        == starfox::simulation::Experience::original
                    && !boot_game.god_mode()
''',
    '''                    && boot_game.experience()
                        == starfox::simulation::Experience::original
                    && boot_game.language()
                        == starfox::localization::Language::english
                    && !boot_game.god_mode()
''',
    "cold boot inicia em English"
)

old_options_test = '''        drive_boot({0, starfox::input::right, 0});
        drive_boot({0, starfox::input::down, 0});
        require(boot_game.pregame_selection() == 3U,
                "pre-game cursor did not reach CUSTOMIZE SCREEN");
        drive_boot({0, starfox::input::down, 0});
        require(boot_game.pregame_selection() == 4U,
                "pre-game cursor did not reach OPTIONS BACK");
        drive_boot({0, starfox::input::a, 0});
'''

new_options_test = '''        drive_boot({0, starfox::input::right, 0});

        drive_boot({0, starfox::input::down, 0});
        require(boot_game.pregame_selection() == 3U
                    && boot_game.language()
                        == starfox::localization::Language::english,
                "pre-game cursor did not reach LANGUAGE");

        drive_boot({0, starfox::input::right, 0});
        require(boot_game.language()
                    == starfox::localization::Language::portuguese_br,
                "LANGUAGE did not enable PT-BR");

        drive_boot({0, starfox::input::left, 0});
        require(boot_game.language()
                    == starfox::localization::Language::english,
                "LANGUAGE did not return to English");

        drive_boot({0, starfox::input::right, 0});
        require(boot_game.language()
                    == starfox::localization::Language::portuguese_br,
                "LANGUAGE did not restore PT-BR");

        drive_boot({0, starfox::input::down, 0});
        require(boot_game.pregame_selection() == 4U,
                "pre-game cursor did not reach CUSTOMIZE SCREEN");

        drive_boot({0, starfox::input::down, 0});
        require(boot_game.pregame_selection() == 5U,
                "pre-game cursor did not reach OPTIONS BACK");

        drive_boot({0, starfox::input::a, 0});
'''

replace_once(
    "tests/simulation_tests.cpp",
    old_options_test,
    new_options_test,
    "testar seletor PT-BR"
)

replace_once(
    "tests/simulation_tests.cpp",
    '''                    && boot_game.crosshair_colour()
                        == starfox::simulation::CrosshairColour::green,
                "OPTIONS did not retain its toggles when returning to setup");
''',
    '''                    && boot_game.crosshair_colour()
                        == starfox::simulation::CrosshairColour::green
                    && boot_game.language()
                        == starfox::localization::Language::portuguese_br,
                "OPTIONS did not retain its toggles when returning to setup");
''',
    "OPTIONS retém idioma PT-BR"
)

print()
print("Patch PT-BR Fase 01 aplicado.")
PY

# ============================================================
# ETAPA 4 — diff
# ============================================================

section "ETAPA 4 — VALIDACAO DO DIFF"

git diff --check

echo
git diff --stat

echo
echo "Arquivos alterados:"
git status --short

# ============================================================
# ETAPA 5 — configurar build isolado
# ============================================================

section "ETAPA 5 — CONFIGURACAO CMAKE"

rm -rf "$BUILD_DIR"

cmake \
    -S "$PROJECT_ROOT" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_EMBED_RUNTIME_ASSETS=OFF

# ============================================================
# ETAPA 6 — build
# ============================================================

section "ETAPA 6 — BUILD"

cmake \
    --build "$BUILD_DIR" \
    -j"$(nproc)"

# ============================================================
# ETAPA 7 — testes
# ============================================================

section "ETAPA 7 — CTEST"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure

# ============================================================
# ETAPA 8 — smoke Original
# ============================================================

section "ETAPA 8 — SMOKE TEST ORIGINAL"

if [[ -s upstream-ultrastarfox/SF.SFC \
   && -s upstream-ultrastarfox/SYMBOLS.TXT ]]
then
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
else
    echo "Smoke test ignorado: assets UltraStarFox ausentes."
fi

# ============================================================
# Resultado
# ============================================================

section "PT-BR FASE 01 CONCLUIDA"

echo "Build:"
echo "  $BUILD_DIR/starfox_pc"
echo
echo "Para testar graficamente:"
echo
echo "  cd \"$PROJECT_ROOT\""
echo "  ./build/linux-ptbr-phase1/starfox_pc \\"
echo "    upstream-ultrastarfox/SF.SFC \\"
echo "    upstream-ultrastarfox/SYMBOLS.TXT \\"
echo "    BOOT"
echo
echo "No menu:"
echo "  OPTIONS -> LANGUAGE -> PORTUGUES BR"

FINAL_RC=0

exit 0
