#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-phase2-reports/$STAMP"
BACKUP_DIR="$REPORT_DIR/backup"
FULL_LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"

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

generate_report() {
    {
        echo "STAR FOX ENHANCED — PT-BR FASE 02"
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
        echo "DIFF STAT"
        echo "============================================================"

        git diff --stat || true

        echo
        echo "============================================================"
        echo "UTF-8 RENDERER"
        echo "============================================================"

        grep -n \
            -E 'draw_utf8|measure_utf8' \
            include/starfox/render/scaled_text_renderer.hpp \
            src/render/scaled_text_renderer.cpp \
            || true

        echo
        echo "============================================================"
        echo "ULTIMAS 180 LINHAS"
        echo "============================================================"

        tail -n 180 "$FULL_LOG" || true

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

    generate_report

    exit "$FINAL_RC"
}

trap on_exit EXIT

section "STAR FOX ENHANCED — PT-BR FASE 02"

# ============================================================
# ETAPA 1 — preflight
# ============================================================

section "ETAPA 1 — PREFLIGHT"

FILES=(
    CMakeLists.txt
    include/starfox/localization/language.hpp
    src/localization/language.cpp
    tests/localization_tests.cpp
    include/starfox/render/scaled_text_renderer.hpp
    src/render/scaled_text_renderer.cpp
    src/app/starfox_pc.cpp
)

for file in "${FILES[@]}"; do
    if [[ ! -s "$file" ]]; then
        echo "ERRO: arquivo ausente:"
        echo "  $file"

        FINAL_RC=10
        exit "$FINAL_RC"
    fi

    echo "OK      $file"
done

echo
echo "Verificando Fase 01..."

grep -q \
    'portuguese_br' \
    include/starfox/localization/language.hpp

grep -q \
    'game.language()' \
    src/app/starfox_pc.cpp

grep -q \
    'LANGUAGE' \
    src/app/runtime_input.cpp

echo "PT-BR Fase 01 detectada."

# ============================================================
# ETAPA 2 — backup
# ============================================================

section "ETAPA 2 — BACKUP"

for file in "${FILES[@]}"; do
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"

    cp -a \
        "$file" \
        "$BACKUP_DIR/$file"

    echo "BACKUP  $file"
done

# ============================================================
# ETAPA 3 — arquivos de localização
# ============================================================

section "ETAPA 3 — DICIONARIO PT-BR"

cat > include/starfox/localization/language.hpp <<'HEADER_EOF'
#pragma once

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

    color_green,
    color_white,
    color_blue,
    color_red,
    color_yellow,
    color_cyan,
    color_magenta,
    color_orange,

    hud_layout,
    reset,
    done,

    controller_remap,
    dpad_choose,
    keyboard,
    action,
    press_key_control,
    left_right_device,
    bind_defaults,
    remap_done,

    count,
};

[[nodiscard]] std::string_view text(
    Language language,
    TextId id) noexcept;

[[nodiscard]] std::string_view language_name(
    Language language) noexcept;

} // namespace starfox::localization
HEADER_EOF

cat > src/localization/language.cpp <<'CPP_EOF'
#include "starfox/localization/language.hpp"

namespace starfox::localization {

std::string_view text(
    Language language,
    TextId id) noexcept {

    const auto pt = language == Language::portuguese_br;

    switch (id) {
    case TextId::title:
        return "STAR FOX ENHANCED";

    case TextId::pregame_setup:
        return pt ? "CONFIGURAÇÃO" : "PRE-GAME SETUP";

    case TextId::options_title:
        return pt ? "OPÇÕES" : "OPTIONS";

    case TextId::experience:
        return pt ? "EXPERIÊNCIA" : "EXPERIENCE";

    case TextId::game_pace:
        return pt ? "RITMO DO JOGO" : "GAME PACE";

    case TextId::render_fps:
        return pt ? "FPS DE RENDERIZAÇÃO" : "RENDER FPS";

    case TextId::display:
        return pt ? "TELA" : "DISPLAY";

    case TextId::controller:
        return pt ? "CONTROLE" : "CONTROLLER";

    case TextId::options:
        return pt ? "OPÇÕES" : "OPTIONS";

    case TextId::start_game:
        return pt ? "INICIAR JOGO" : "START GAME";

    case TextId::god_mode:
        return pt ? "MODO DEUS" : "GOD MODE";

    case TextId::onscreen_fps:
        return pt ? "FPS NA TELA" : "ON-SCREEN FPS";

    case TextId::crosshair_color:
        return pt ? "COR DA MIRA" : "CROSSHAIR COLOR";

    case TextId::language:
        return pt ? "IDIOMA" : "LANGUAGE";

    case TextId::customize_screen:
        return pt ? "AJUSTAR TELA" : "CUSTOMIZE SCREEN";

    case TextId::back:
        return pt ? "VOLTAR" : "BACK";

    case TextId::on:
        return pt ? "LIGADO" : "ON";

    case TextId::off:
        return pt ? "DESLIGADO" : "OFF";

    case TextId::open:
        return pt ? "A  ABRIR" : "A  OPEN";

    case TextId::remap:
        return pt ? "A  MAPEAR" : "A  REMAP";

    case TextId::change_hint:
        return pt
            ? "A/ESQ/DIR  ALTERA"
            : "A/LEFT/RIGHT  CHANGE";

    case TextId::back_hint:
        return pt ? "B  VOLTAR" : "B  BACK";

    case TextId::choose_hint:
        return pt
            ? "D-PAD ESCOLHE  A CONFIRMA"
            : "D-PAD CHOOSE  A SELECT";

    case TextId::begin_hint:
        return pt ? "START  INICIA" : "START  BEGIN";

    case TextId::unlocked_20_hz:
        return pt ? "20 HZ LIVRE" : "UNLOCKED 20 HZ";

    case TextId::original_speed:
        return "ORIGINAL";

    case TextId::display_4_3:
        return pt ? "4 POR 3 PADRÃO" : "4 BY 3 STANDARD";

    case TextId::display_16_9:
        return pt ? "16 POR 9 AMPLO" : "16 BY 9 WIDE";

    case TextId::display_16_10:
        return pt ? "16 POR 10 AMPLO" : "16 BY 10 WIDE";

    case TextId::display_21_9:
        return pt ? "21 POR 9 ULTRA" : "21 BY 9 ULTRA";

    case TextId::display_32_9:
        return pt ? "32 POR 9 SUPER" : "32 BY 9 SUPER";

    case TextId::original_experience:
        return "ORIGINAL";

    case TextId::starfox_ex_experience:
        return "STARFOX EX";

    case TextId::color_green:
        return pt ? "VERDE" : "GREEN";

    case TextId::color_white:
        return pt ? "BRANCO" : "WHITE";

    case TextId::color_blue:
        return pt ? "AZUL" : "BLUE";

    case TextId::color_red:
        return pt ? "VERMELHO" : "RED";

    case TextId::color_yellow:
        return pt ? "AMARELO" : "YELLOW";

    case TextId::color_cyan:
        return pt ? "CIANO" : "CYAN";

    case TextId::color_magenta:
        return "MAGENTA";

    case TextId::color_orange:
        return pt ? "LARANJA" : "ORANGE";

    case TextId::hud_layout:
        return pt ? "LAYOUT DO HUD" : "HUD LAYOUT";

    case TextId::reset:
        return pt ? "RESETAR" : "RESET";

    case TextId::done:
        return pt ? "CONCLUIR" : "DONE";

    case TextId::controller_remap:
        return pt ? "MAPEAR CONTROLE" : "CONTROLLER REMAP";

    case TextId::dpad_choose:
        return pt ? "D-PAD  ESCOLHE" : "D-PAD  CHOOSE";

    case TextId::keyboard:
        return pt ? "TECLADO" : "KEYBOARD";

    case TextId::action:
        return pt ? "AÇÃO" : "ACTION";

    case TextId::press_key_control:
        return pt
            ? "PRESSIONE TECLA OU CONTROLE"
            : "PRESS A KEY OR CONTROL";

    case TextId::left_right_device:
        return pt
            ? "ESQ/DIR  DISPOSITIVO"
            : "LEFT/RIGHT  DEVICE";

    case TextId::bind_defaults:
        return pt
            ? "A  MAPEAR   Y  PADRÃO"
            : "A  BIND   Y  DEFAULTS";

    case TextId::remap_done:
        return pt
            ? "B/START/ESC  CONCLUIR"
            : "B/START/ESC  DONE";

    case TextId::count:
    default:
        return {};
    }
}

std::string_view language_name(Language language) noexcept {
    return language == Language::portuguese_br
        ? std::string_view{"PORTUGUÊS BR"}
        : std::string_view{"ENGLISH"};
}

} // namespace starfox::localization
CPP_EOF

cat > tests/localization_tests.cpp <<'CPP_EOF'
#include "starfox/localization/language.hpp"

#include <cstdlib>
#include <iostream>
#include <string_view>

namespace {

void require(bool condition, std::string_view message) {
    if (!condition) {
        std::cerr
            << "localization test failed: "
            << message
            << '\n';

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
        text(Language::portuguese_br, TextId::pregame_setup)
            == "CONFIGURAÇÃO",
        "PT-BR CONFIGURACAO lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::options)
            == "OPÇÕES",
        "PT-BR OPCOES lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::experience)
            == "EXPERIÊNCIA",
        "PT-BR EXPERIENCIA lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::display_4_3)
            == "4 POR 3 PADRÃO",
        "PT-BR PADRAO lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::action)
            == "AÇÃO",
        "PT-BR ACAO lost UTF-8 accents");

    require(
        language_name(Language::portuguese_br)
            == "PORTUGUÊS BR",
        "PT-BR language label lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::color_green)
            == "VERDE",
        "PT-BR green translation is wrong");

    require(
        text(Language::portuguese_br, TextId::color_red)
            == "VERMELHO",
        "PT-BR red translation is wrong");

    std::cout << "localization UTF-8 tests passed\n";

    return 0;
}
CPP_EOF

# ============================================================
# ETAPA 4 — API UTF-8 no renderer
# ============================================================

section "ETAPA 4 — RENDERER UTF-8"

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])

header = root / "include/starfox/render/scaled_text_renderer.hpp"
cpp = root / "src/render/scaled_text_renderer.cpp"

h = header.read_text(encoding="utf-8")

if "void draw_utf8(" not in h:
    anchor = '''    void draw_ascii(
        std::string_view text,
        std::int32_t x,
        std::int32_t y,
        Framebuffer& target,
        std::uint8_t colour = 14U,
        std::uint8_t colour_index_base = 7U * 16U) const;

    [[nodiscard]] std::int32_t measure_ascii(std::string_view text) const;
'''

    replacement = '''    void draw_ascii(
        std::string_view text,
        std::int32_t x,
        std::int32_t y,
        Framebuffer& target,
        std::uint8_t colour = 14U,
        std::uint8_t colour_index_base = 7U * 16U) const;

    // Host-interface UTF-8 renderer. ASCII characters continue using the
    // original Star Fox ROM font. Portuguese Latin characters reuse the
    // corresponding ROM glyph and add their diacritic on the host layer.
    void draw_utf8(
        std::string_view text,
        std::int32_t x,
        std::int32_t y,
        Framebuffer& target,
        std::uint8_t colour = 14U,
        std::uint8_t colour_index_base = 7U * 16U) const;

    [[nodiscard]] std::int32_t measure_ascii(std::string_view text) const;

    [[nodiscard]] std::int32_t measure_utf8(
        std::string_view text) const;
'''

    if anchor not in h:
        raise RuntimeError(
            "Nao encontrei a declaracao draw_ascii/measure_ascii."
        )

    h = h.replace(anchor, replacement, 1)

    header.write_text(h, encoding="utf-8")

    print("PATCH   scaled_text_renderer.hpp")
else:
    print("JA OK   scaled_text_renderer.hpp")

text = cpp.read_text(encoding="utf-8")

if "#include <utility>" not in text:
    text = text.replace(
        "#include <vector>\n",
        "#include <vector>\n#include <utility>\n",
        1
    )

if "void ScaledTextRenderer::draw_utf8(" not in text:

    marker = "\n} // namespace starfox::render\n"

    if marker not in text:
        raise RuntimeError(
            "Fechamento namespace starfox::render nao encontrado."
        )

    implementation = r'''
namespace {

enum class HostAccent {
    none,
    acute,
    grave,
    circumflex,
    tilde,
    cedilla,
};

struct HostGlyph {
    std::uint8_t ascii{};
    HostAccent accent{HostAccent::none};
};

struct DecodedHostCodepoint {
    std::uint32_t value{};
    std::size_t bytes{1U};
};

DecodedHostCodepoint decode_host_utf8(
    std::string_view text,
    std::size_t offset) noexcept {

    const auto first = static_cast<std::uint8_t>(
        text[offset]);

    if (first < 0x80U) {
        return {first, 1U};
    }

    if ((first & 0xe0U) == 0xc0U
        && offset + 1U < text.size()) {

        const auto second = static_cast<std::uint8_t>(
            text[offset + 1U]);

        if ((second & 0xc0U) == 0x80U) {
            return {
                static_cast<std::uint32_t>(
                    ((first & 0x1fU) << 6U)
                    | (second & 0x3fU)),
                2U,
            };
        }
    }

    if ((first & 0xf0U) == 0xe0U
        && offset + 2U < text.size()) {

        const auto second = static_cast<std::uint8_t>(
            text[offset + 1U]);

        const auto third = static_cast<std::uint8_t>(
            text[offset + 2U]);

        if ((second & 0xc0U) == 0x80U
            && (third & 0xc0U) == 0x80U) {

            return {
                static_cast<std::uint32_t>(
                    ((first & 0x0fU) << 12U)
                    | ((second & 0x3fU) << 6U)
                    | (third & 0x3fU)),
                3U,
            };
        }
    }

    return {
        static_cast<std::uint32_t>('?'),
        1U,
    };
}

HostGlyph host_glyph(std::uint32_t codepoint) noexcept {

    if (codepoint <= 0x7fU) {
        return {
            static_cast<std::uint8_t>(codepoint),
            HostAccent::none,
        };
    }

    switch (codepoint) {
    // A / a
    case 0x00c0U:
        return {'A', HostAccent::grave};
    case 0x00c1U:
        return {'A', HostAccent::acute};
    case 0x00c2U:
        return {'A', HostAccent::circumflex};
    case 0x00c3U:
        return {'A', HostAccent::tilde};

    case 0x00e0U:
        return {'a', HostAccent::grave};
    case 0x00e1U:
        return {'a', HostAccent::acute};
    case 0x00e2U:
        return {'a', HostAccent::circumflex};
    case 0x00e3U:
        return {'a', HostAccent::tilde};

    // C / c
    case 0x00c7U:
        return {'C', HostAccent::cedilla};
    case 0x00e7U:
        return {'c', HostAccent::cedilla};

    // E / e
    case 0x00c9U:
        return {'E', HostAccent::acute};
    case 0x00caU:
        return {'E', HostAccent::circumflex};

    case 0x00e9U:
        return {'e', HostAccent::acute};
    case 0x00eaU:
        return {'e', HostAccent::circumflex};

    // I / i
    case 0x00cdU:
        return {'I', HostAccent::acute};
    case 0x00edU:
        return {'i', HostAccent::acute};

    // O / o
    case 0x00d3U:
        return {'O', HostAccent::acute};
    case 0x00d4U:
        return {'O', HostAccent::circumflex};
    case 0x00d5U:
        return {'O', HostAccent::tilde};

    case 0x00f3U:
        return {'o', HostAccent::acute};
    case 0x00f4U:
        return {'o', HostAccent::circumflex};
    case 0x00f5U:
        return {'o', HostAccent::tilde};

    // U / u
    case 0x00daU:
        return {'U', HostAccent::acute};
    case 0x00faU:
        return {'u', HostAccent::acute};

    default:
        return {'?', HostAccent::none};
    }
}

} // namespace

void ScaledTextRenderer::draw_utf8(
    std::string_view text,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour,
    std::uint8_t colour_index_base) const {

    const auto output_colour = static_cast<std::uint8_t>(
        colour_index_base + (colour & 0x0fU));

    const auto glyph_width =
        [this](std::uint8_t ascii) -> std::uint8_t {

        if (ascii == 32U) {
            return 5U;
        }

        if (ascii < 32U) {
            return 0U;
        }

        const auto translated = rom_->read8(
            game_font_translation_
            + static_cast<std::uint32_t>(
                ascii - 32U));

        return rom_->read8(
            game_font_widths_ + translated);
    };

    const auto draw_base =
        [this, &target, output_colour, &glyph_width](
            std::uint8_t ascii,
            std::int32_t draw_x,
            std::int32_t draw_y) {

        const auto width = glyph_width(ascii);

        if (ascii <= 32U || width == 0U) {
            return;
        }

        const auto translated = rom_->read8(
            game_font_translation_
            + static_cast<std::uint32_t>(
                ascii - 32U));

        const auto glyph =
            game_font_glyphs_
            + static_cast<std::uint32_t>(
                translated) * 24U;

        for (std::int32_t row = 0;
             row < 12;
             ++row) {

            const auto bits = rom_->read16(
                glyph
                + static_cast<std::uint32_t>(
                    row * 2));

            for (std::int32_t column = 0;
                 column < width;
                 ++column) {

                if ((bits
                    & (0x8000U >> column)) != 0U) {

                    target.set(
                        draw_x + column,
                        draw_y + row,
                        output_colour);
                }
            }
        }
    };

    const auto draw_accent =
        [&target, output_colour](
            HostAccent accent,
            std::int32_t draw_x,
            std::int32_t draw_y,
            std::uint8_t width) {

        if (accent == HostAccent::none
            || width == 0U) {
            return;
        }

        const auto middle =
            std::max<std::int32_t>(
                1,
                static_cast<std::int32_t>(
                    width) / 2);

        const auto pixel =
            [&target, output_colour](
                std::int32_t px,
                std::int32_t py) {

            target.set(
                px,
                py,
                output_colour);
        };

        switch (accent) {
        case HostAccent::acute:
            pixel(
                draw_x + middle,
                draw_y - 2);

            pixel(
                draw_x + middle + 1,
                draw_y - 3);

            break;

        case HostAccent::grave:
            pixel(
                draw_x + middle,
                draw_y - 2);

            pixel(
                draw_x + middle - 1,
                draw_y - 3);

            break;

        case HostAccent::circumflex:
            pixel(
                draw_x + middle - 1,
                draw_y - 2);

            pixel(
                draw_x + middle,
                draw_y - 3);

            pixel(
                draw_x + middle + 1,
                draw_y - 2);

            break;

        case HostAccent::tilde:
            pixel(
                draw_x + middle - 2,
                draw_y - 2);

            pixel(
                draw_x + middle - 1,
                draw_y - 3);

            pixel(
                draw_x + middle,
                draw_y - 3);

            pixel(
                draw_x + middle + 1,
                draw_y - 2);

            break;

        case HostAccent::cedilla:
            pixel(
                draw_x + middle,
                draw_y + 12);

            pixel(
                draw_x + middle - 1,
                draw_y + 13);

            break;

        case HostAccent::none:
        default:
            break;
        }
    };

    const auto start_x = x;

    std::size_t offset{};

    while (offset < text.size()) {

        const auto decoded =
            decode_host_utf8(
                text,
                offset);

        offset += decoded.bytes;

        if (decoded.value == '\n') {
            x = start_x;
            y += 15;
            continue;
        }

        if (decoded.value == '\r') {
            continue;
        }

        const auto glyph =
            host_glyph(decoded.value);

        const auto width =
            glyph_width(glyph.ascii);

        draw_base(
            glyph.ascii,
            x,
            y);

        draw_accent(
            glyph.accent,
            x,
            y,
            width);

        x += width;
    }
}

std::int32_t ScaledTextRenderer::measure_utf8(
    std::string_view text) const {

    const auto glyph_width =
        [this](std::uint8_t ascii)
            -> std::uint8_t {

        if (ascii == 32U) {
            return 5U;
        }

        if (ascii < 32U) {
            return 0U;
        }

        const auto translated = rom_->read8(
            game_font_translation_
            + static_cast<std::uint32_t>(
                ascii - 32U));

        return rom_->read8(
            game_font_widths_ + translated);
    };

    std::int32_t current{};
    std::int32_t maximum{};

    std::size_t offset{};

    while (offset < text.size()) {

        const auto decoded =
            decode_host_utf8(
                text,
                offset);

        offset += decoded.bytes;

        if (decoded.value == '\n') {
            maximum =
                std::max(
                    maximum,
                    current);

            current = 0;

            continue;
        }

        if (decoded.value == '\r') {
            continue;
        }

        const auto glyph =
            host_glyph(decoded.value);

        current +=
            static_cast<std::int32_t>(
                glyph_width(glyph.ascii));
    }

    return std::max(
        maximum,
        current);
}
'''

    text = text.replace(
        marker,
        "\n" + implementation + marker,
        1
    )

    cpp.write_text(
        text,
        encoding="utf-8"
    )

    print("PATCH   scaled_text_renderer.cpp")
else:
    print("JA OK   scaled_text_renderer.cpp")
PY

# ============================================================
# ETAPA 5 — frontend
# ============================================================

section "ETAPA 5 — FRONTEND PT-BR"

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])
path = root / "src/app/starfox_pc.cpp"

text = path.read_text(encoding="utf-8")


def replace_once(old, new, description):
    global text

    if new in text:
        print(f"JA OK   {description}")
        return

    if old not in text:
        raise RuntimeError(
            "Nao encontrei trecho: "
            + description
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   "
        + description
    )


# ------------------------------------------------------------
# Cores da mira
# ------------------------------------------------------------

old = '''std::string_view crosshair_colour_name(
    starfox::simulation::CrosshairColour colour) noexcept {
    switch (colour) {
    case starfox::simulation::CrosshairColour::white:
        return "WHITE";
    case starfox::simulation::CrosshairColour::blue:
        return "BLUE";
    case starfox::simulation::CrosshairColour::red:
        return "RED";
    case starfox::simulation::CrosshairColour::yellow:
        return "YELLOW";
    case starfox::simulation::CrosshairColour::cyan:
        return "CYAN";
    case starfox::simulation::CrosshairColour::magenta:
        return "MAGENTA";
    case starfox::simulation::CrosshairColour::orange:
        return "ORANGE";
    case starfox::simulation::CrosshairColour::green:
    default:
        return "GREEN";
    }
}
'''

new = '''std::string_view crosshair_colour_name(
    starfox::simulation::CrosshairColour colour,
    starfox::localization::Language language) noexcept {

    using starfox::localization::TextId;

    switch (colour) {
    case starfox::simulation::CrosshairColour::white:
        return starfox::localization::text(
            language, TextId::color_white);

    case starfox::simulation::CrosshairColour::blue:
        return starfox::localization::text(
            language, TextId::color_blue);

    case starfox::simulation::CrosshairColour::red:
        return starfox::localization::text(
            language, TextId::color_red);

    case starfox::simulation::CrosshairColour::yellow:
        return starfox::localization::text(
            language, TextId::color_yellow);

    case starfox::simulation::CrosshairColour::cyan:
        return starfox::localization::text(
            language, TextId::color_cyan);

    case starfox::simulation::CrosshairColour::magenta:
        return starfox::localization::text(
            language, TextId::color_magenta);

    case starfox::simulation::CrosshairColour::orange:
        return starfox::localization::text(
            language, TextId::color_orange);

    case starfox::simulation::CrosshairColour::green:
    default:
        return starfox::localization::text(
            language, TextId::color_green);
    }
}
'''

replace_once(
    old,
    new,
    "crosshair localizado"
)

replace_once(
    '''                        const auto crosshair = crosshair_colour_name(
                            game.crosshair_colour());
''',
    '''                        const auto crosshair = crosshair_colour_name(
                            game.crosshair_colour(),
                            game.language());
''',
    "idioma das cores"
)

# ------------------------------------------------------------
# Renderer das linhas principais do menu
# ------------------------------------------------------------

replace_once(
    '''                    text_renderer.draw_ascii(text,
                        128 - text_renderer.measure_ascii(text) / 2
                            + viewport_origin,
                        y, framebuffer, colour);
''',
    '''                    text_renderer.draw_utf8(text,
                        128 - text_renderer.measure_utf8(text) / 2
                            + viewport_origin,
                        y, framebuffer, colour);
''',
    "draw_centred usa UTF-8"
)

replace_once(
    '''                        text_renderer.draw_ascii(label,
                            menu_label_x + viewport_origin,
                            y, framebuffer, colour);
''',
    '''                        text_renderer.draw_utf8(label,
                            menu_label_x + viewport_origin,
                            y, framebuffer, colour);
''',
    "labels usam UTF-8"
)

replace_once(
    '''                            text_renderer.draw_ascii(value,
                                menu_value_right
                                    - text_renderer.measure_ascii(value)
                                    + viewport_origin,
                                y, framebuffer, colour);
''',
    '''                            text_renderer.draw_utf8(value,
                                menu_value_right
                                    - text_renderer.measure_utf8(value)
                                    + viewport_origin,
                                y, framebuffer, colour);
''',
    "valores usam UTF-8"
)

# ------------------------------------------------------------
# HUD editor
# ------------------------------------------------------------

replace_once(
    '''                    const auto editor_title = std::string{"HUD LAYOUT  "}
                        + (game.experience()
''',
    '''                    const auto editor_title =
                        std::string{tr(
                            starfox::localization::TextId::hud_layout)}
                        + "  "
                        + (game.experience()
''',
    "titulo do editor HUD"
)

replace_once(
    '''                    text_renderer.draw_ascii(editor_title,
                        static_cast<std::int32_t>(display_width / 2U)
                            - static_cast<std::int32_t>(editor_title.size() * 4U),
                        2, framebuffer, 14U);
''',
    '''                    text_renderer.draw_utf8(editor_title,
                        static_cast<std::int32_t>(display_width / 2U)
                            - text_renderer.measure_utf8(editor_title) / 2,
                        2, framebuffer, 14U);
''',
    "titulo HUD usa UTF-8"
)

replace_once(
    '''                    text_renderer.draw_ascii("Y RESET", reset.x + 6,
                        reset.y + 3, framebuffer, 15U);
                    text_renderer.draw_ascii("B DONE", done.x + 2,
                        done.y + 3, framebuffer, 15U);
''',
    '''                    const auto reset_text =
                        std::string{"Y "}
                        + std::string{tr(
                            starfox::localization::TextId::reset)};

                    const auto done_text =
                        std::string{"B "}
                        + std::string{tr(
                            starfox::localization::TextId::done)};

                    text_renderer.draw_utf8(
                        reset_text,
                        reset.x + 6,
                        reset.y + 3,
                        framebuffer,
                        15U);

                    text_renderer.draw_utf8(
                        done_text,
                        done.x + 2,
                        done.y + 3,
                        framebuffer,
                        15U);
''',
    "botoes do HUD editor"
)

# ------------------------------------------------------------
# Remapeamento
# ------------------------------------------------------------

replace_once(
    '''                    draw_centred("CONTROLLER REMAP", 34, 14U);
                    draw_centred("D-PAD  CHOOSE", 51, 10U);
''',
    '''                    draw_centred(
                        tr(starfox::localization::TextId::controller_remap),
                        34, 14U);

                    draw_centred(
                        tr(starfox::localization::TextId::dpad_choose),
                        51, 10U);
''',
    "cabecalho remap"
)

replace_once(
    '''                        ? std::string{"KEYBOARD"}
                        : starfox::app::gamepad_device_label(gamepad);
''',
    '''                        ? std::string{tr(
                            starfox::localization::TextId::keyboard)}
                        : starfox::app::gamepad_device_label(gamepad);
''',
    "TECLADO"
)

replace_once(
    '''                    const auto action = std::string{"ACTION  "}
                        + std::string{starfox::app::InputBindings::action_name(
''',
    '''                    const auto action =
                        std::string{tr(
                            starfox::localization::TextId::action)}
                        + "  "
                        + std::string{starfox::app::InputBindings::action_name(
''',
    "ACAO"
)

replace_once(
    '''                    auto binding = remap_menu.waiting_for_input
                        ? std::string{"PRESS A KEY OR CONTROL"}
                        : bindings.binding_name(
''',
    '''                    auto binding = remap_menu.waiting_for_input
                        ? std::string{tr(
                            starfox::localization::TextId::press_key_control)}
                        : bindings.binding_name(
''',
    "prompt remap"
)

replace_once(
    '''                    draw_centred("LEFT/RIGHT  DEVICE", 143, 13U);
                    draw_centred("A  BIND   Y  DEFAULTS", 158, 13U);
                    draw_centred("B/START/ESC  DONE", 177, 13U);
''',
    '''                    draw_centred(
                        tr(starfox::localization::TextId::left_right_device),
                        143, 13U);

                    draw_centred(
                        tr(starfox::localization::TextId::bind_defaults),
                        158, 13U);

                    draw_centred(
                        tr(starfox::localization::TextId::remap_done),
                        177, 13U);
''',
    "instrucoes remap"
)

# ------------------------------------------------------------
# Override de idioma para testes
# ------------------------------------------------------------

anchor = '''            game.set_language(
                static_cast<starfox::localization::Language>(
                    saved_pregame.language));
'''

addition = '''            game.set_language(
                static_cast<starfox::localization::Language>(
                    saved_pregame.language));

            if (const auto* forced_language =
                    std::getenv("STARFOX_TEST_LANGUAGE")) {

                const auto language =
                    std::string_view{forced_language};

                game.set_language(
                    language == "PT_BR"
                        || language == "pt_BR"
                        || language == "pt-BR"
                    ? starfox::localization::Language::portuguese_br
                    : starfox::localization::Language::english);
            }
'''

replace_once(
    anchor,
    addition,
    "STARFOX_TEST_LANGUAGE"
)

path.write_text(
    text,
    encoding="utf-8"
)
PY

# ============================================================
# ETAPA 6 — smoke test PT-BR no CMake
# ============================================================

section "ETAPA 6 — TESTE PT-BR"

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])
path = root / "CMakeLists.txt"

text = path.read_text(encoding="utf-8")

if "starfox_runtime_smoke_ptbr" not in text:

    anchor = '''            set_tests_properties(starfox_runtime_smoke PROPERTIES
                ENVIRONMENT
                    "SDL_VIDEODRIVER=dummy;SDL_AUDIODRIVER=dummy;STARFOX_TEST_EXPERIENCE=ORIGINAL;STARFOX_TEST_FRAMES=6"
                TIMEOUT 10
            )
'''

    addition = anchor + '''
            add_test(
                NAME starfox_runtime_smoke_ptbr
                COMMAND starfox_pc
                        "${CMAKE_CURRENT_SOURCE_DIR}/upstream-ultrastarfox/SF.SFC"
                        "${CMAKE_CURRENT_SOURCE_DIR}/upstream-ultrastarfox/SYMBOLS.TXT"
                        LEVEL1_1
            )

            set_tests_properties(starfox_runtime_smoke_ptbr PROPERTIES
                ENVIRONMENT
                    "SDL_VIDEODRIVER=dummy;SDL_AUDIODRIVER=dummy;STARFOX_TEST_EXPERIENCE=ORIGINAL;STARFOX_TEST_LANGUAGE=PT_BR;STARFOX_TEST_FRAMES=6"
                TIMEOUT 10
            )
'''

    if anchor not in text:
        raise RuntimeError(
            "Nao encontrei starfox_runtime_smoke da Fase 01."
        )

    text = text.replace(
        anchor,
        addition,
        1
    )

    path.write_text(
        text,
        encoding="utf-8"
    )

    print("PATCH   CMake PT-BR smoke")
else:
    print("JA OK   CMake PT-BR smoke")
PY

# ============================================================
# ETAPA 7 — validações
# ============================================================

section "ETAPA 7 — VALIDACOES"

echo "Validando UTF-8 dos arquivos..."

python3 <<'PY'
from pathlib import Path

files = [
    Path("include/starfox/localization/language.hpp"),
    Path("src/localization/language.cpp"),
    Path("tests/localization_tests.cpp"),
    Path("include/starfox/render/scaled_text_renderer.hpp"),
    Path("src/render/scaled_text_renderer.cpp"),
    Path("src/app/starfox_pc.cpp"),
]

for path in files:
    path.read_text(encoding="utf-8")
    print(f"UTF8 OK  {path}")
PY

echo
echo "git diff --check:"

git diff --check

echo
echo "Diff:"

git diff --stat

# ============================================================
# ETAPA 8 — reconfiguração incremental
# ============================================================

section "ETAPA 8 — CMAKE INCREMENTAL"

cmake \
    -S "$PROJECT_ROOT" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_EMBED_RUNTIME_ASSETS=OFF

# ============================================================
# ETAPA 9 — build
# ============================================================

section "ETAPA 9 — BUILD"

cmake \
    --build "$BUILD_DIR" \
    -j"$(nproc)"

# ============================================================
# ETAPA 10 — testes
# ============================================================

section "ETAPA 10 — CTEST"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure

# ============================================================
# ETAPA 11 — smoke explícito PT-BR
# ============================================================

section "ETAPA 11 — SMOKE PT-BR"

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

# ============================================================
# Resultado
# ============================================================

section "PT-BR FASE 02 CONCLUIDA"

echo "Suporte UTF-8 PT-BR instalado."
echo
echo "Caracteres suportados:"
echo "  Á À Â Ã"
echo "  á à â ã"
echo "  Ç ç"
echo "  É Ê é ê"
echo "  Í í"
echo "  Ó Ô Õ ó ô õ"
echo "  Ú ú"
echo
echo "Executavel:"
echo
echo "  $BUILD_DIR/starfox_pc"
echo
echo "Teste grafico:"
echo
echo "  $BUILD_DIR/starfox_pc \\"
echo "    upstream-ultrastarfox/SF.SFC \\"
echo "    upstream-ultrastarfox/SYMBOLS.TXT \\"
echo "    BOOT"

FINAL_RC=0

exit 0
