#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass01/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 01"
echo "Tile-row cache + direct framebuffer rows + LTO"
echo "============================================================"
echo

FILES=(
    include/starfox/render/framebuffer.hpp
    src/render/background_renderer.cpp
    ports/switch/CMakeLists.txt
)

for file in "${FILES[@]}"
do
    test -f "$file" || {
        echo "ERRO: arquivo ausente:"
        echo "  $file"
        exit 10
    }

    mkdir -p "$REPORT_DIR/backup/$(dirname "$file")"

    cp -a \
        "$file" \
        "$REPORT_DIR/backup/$file"
done

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])


def replace_once(text, old, new, description):
    if new in text:
        print(f"JA OK   {description}")
        return text

    if old not in text:
        raise RuntimeError(
            f"Trecho não encontrado: {description}"
        )

    print(f"PATCH   {description}")
    return text.replace(old, new, 1)


# ============================================================
# 1. FRAMEBUFFER: acesso direto a uma scanline
# ============================================================

path = root / "include/starfox/render/framebuffer.hpp"
text = path.read_text(encoding="utf-8")

old = '''    [[nodiscard]] const std::vector<std::uint8_t>& pixels() const noexcept { return pixels_; }

    void resize(std::uint32_t width, std::uint32_t height) {
'''

new = '''    [[nodiscard]] const std::vector<std::uint8_t>& pixels() const noexcept { return pixels_; }

    // Hot render paths already guarantee that y is inside the framebuffer.
    // Returning the row once avoids one bounds check and one y*width
    // multiplication for every individual pixel written by the SNES
    // background renderer.
    [[nodiscard]] std::uint8_t* row_data(
        std::uint32_t y) noexcept {

        return pixels_.data()
            + static_cast<std::size_t>(y) * width_;
    }

    [[nodiscard]] const std::uint8_t* row_data(
        std::uint32_t y) const noexcept {

        return pixels_.data()
            + static_cast<std::size_t>(y) * width_;
    }

    void resize(std::uint32_t width, std::uint32_t height) {
'''

text = replace_once(
    text,
    old,
    new,
    "Framebuffer::row_data()"
)

path.write_text(text, encoding="utf-8")


# ============================================================
# 2. BACKGROUND RENDERER
#
# Antes:
#
# pixel 0 -> lê os mesmos bytes do tile
# pixel 1 -> lê os mesmos bytes do tile
# ...
# pixel 7 -> lê os mesmos bytes do tile
#
# Agora:
#
# tile row -> lê bitplanes UMA vez
#          -> decodifica 8 pixels
#          -> reutiliza os 8 resultados
#
# Também evitamos reler a entrada do tilemap enquanto permanecemos
# dentro do mesmo tile.
# ============================================================

path = root / "src/render/background_renderer.cpp"
text = path.read_text(encoding="utf-8")


# Os helpers antigos continuam disponíveis como referência/fallback,
# mas o caminho quente passará a utilizar linhas decodificadas.
for function in (
    "tile_pixel_4bpp",
    "tile_pixel_2bpp",
    "tile_pixel_8bpp",
):
    old_marker = f"std::uint8_t {function}("
    new_marker = f"[[maybe_unused]] std::uint8_t {function}("

    if new_marker not in text:
        if old_marker not in text:
            raise RuntimeError(
                f"Helper {function} não encontrado"
            )

        text = text.replace(
            old_marker,
            new_marker,
            1
        )


helper_marker = '''using TileRow = std::array<std::uint8_t, 8>;
'''

if helper_marker not in text:

    anchor = '''bool selected_priority(std::uint16_t tile, TilePriorityPass pass) noexcept {
'''

    if anchor not in text:
        raise RuntimeError(
            "selected_priority não encontrado"
        )

    helpers = r'''
using TileRow = std::array<std::uint8_t, 8>;

TileRow decode_tile_row_4bpp(
    const simulation::SnesPpuState& ppu,
    std::uint16_t character_base,
    std::uint16_t tile,
    std::uint32_t y) noexcept {

    if ((tile & 0x8000U) != 0U) {
        y = 7U - y;
    }

    const auto tile_number =
        static_cast<std::uint32_t>(
            tile & 0x03ffU);

    const auto base =
        (static_cast<std::uint32_t>(
            character_base) * 2U
            + tile_number * 32U
            + y * 2U)
        & 0xffffU;

    const auto plane01 =
        static_cast<std::uint16_t>(
            ppu.vram[base])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (base + 1U) & 0xffffU])
            << 8U);

    const auto plane23 =
        static_cast<std::uint16_t>(
            ppu.vram[
                (base + 16U) & 0xffffU])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (base + 17U) & 0xffffU])
            << 8U);

    const auto flip_x =
        (tile & 0x4000U) != 0U;

    TileRow result{};

    for (std::uint32_t x = 0U;
         x < 8U;
         ++x) {

        const auto source_x =
            flip_x
                ? 7U - x
                : x;

        const auto mask =
            static_cast<std::uint8_t>(
                0x80U >> source_x);

        result[x] =
            static_cast<std::uint8_t>(
                ((plane01 & mask) != 0U
                    ? 1U : 0U)
                | ((plane01
                        & (static_cast<std::uint16_t>(
                            mask) << 8U))
                    != 0U
                    ? 2U : 0U)
                | ((plane23 & mask) != 0U
                    ? 4U : 0U)
                | ((plane23
                        & (static_cast<std::uint16_t>(
                            mask) << 8U))
                    != 0U
                    ? 8U : 0U));
    }

    return result;
}

TileRow decode_tile_row_2bpp(
    const simulation::SnesPpuState& ppu,
    std::uint16_t character_base,
    std::uint16_t tile,
    std::uint32_t y) noexcept {

    if ((tile & 0x8000U) != 0U) {
        y = 7U - y;
    }

    const auto tile_number =
        static_cast<std::uint32_t>(
            tile & 0x03ffU);

    const auto base =
        (static_cast<std::uint32_t>(
            character_base) * 2U
            + tile_number * 16U
            + y * 2U)
        & 0xffffU;

    const auto planes =
        static_cast<std::uint16_t>(
            ppu.vram[base])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (base + 1U) & 0xffffU])
            << 8U);

    const auto flip_x =
        (tile & 0x4000U) != 0U;

    TileRow result{};

    for (std::uint32_t x = 0U;
         x < 8U;
         ++x) {

        const auto source_x =
            flip_x
                ? 7U - x
                : x;

        const auto mask =
            static_cast<std::uint8_t>(
                0x80U >> source_x);

        result[x] =
            static_cast<std::uint8_t>(
                ((planes & mask) != 0U
                    ? 1U : 0U)
                | ((planes
                        & (static_cast<std::uint16_t>(
                            mask) << 8U))
                    != 0U
                    ? 2U : 0U));
    }

    return result;
}

TileRow decode_tile_row_8bpp(
    const simulation::SnesPpuState& ppu,
    std::uint16_t character_base,
    std::uint16_t tile,
    std::uint32_t y) noexcept {

    if ((tile & 0x8000U) != 0U) {
        y = 7U - y;
    }

    const auto tile_number =
        static_cast<std::uint32_t>(
            tile & 0x03ffU);

    const auto base =
        (static_cast<std::uint32_t>(
            character_base) * 2U
            + tile_number * 64U
            + y * 2U)
        & 0xffffU;

    const auto flip_x =
        (tile & 0x4000U) != 0U;

    TileRow result{};

    for (std::uint32_t x = 0U;
         x < 8U;
         ++x) {

        const auto source_x =
            flip_x
                ? 7U - x
                : x;

        const auto mask =
            static_cast<std::uint8_t>(
                0x80U >> source_x);

        std::uint8_t colour{};

        for (std::uint32_t pair = 0U;
             pair < 4U;
             ++pair) {

            const auto pair_base =
                (base + pair * 16U)
                & 0xffffU;

            if ((ppu.vram[pair_base]
                    & mask) != 0U) {

                colour =
                    static_cast<std::uint8_t>(
                        colour
                        | (1U
                            << (pair * 2U)));
            }

            if ((ppu.vram[
                    (pair_base + 1U)
                        & 0xffffU]
                    & mask) != 0U) {

                colour =
                    static_cast<std::uint8_t>(
                        colour
                        | (2U
                            << (pair * 2U)));
            }
        }

        result[x] = colour;
    }

    return result;
}

'''

    text = text.replace(
        anchor,
        helpers + anchor,
        1
    )

    print("PATCH   tile-row decoders")
else:
    print("JA OK   tile-row decoders")


def section_between(source, begin, end=None):
    start = source.find(begin)

    if start < 0:
        raise RuntimeError(
            f"Função não encontrada: {begin}"
        )

    if end is None:
        finish = len(source)
    else:
        finish = source.find(
            end,
            start
        )

        if finish < 0:
            raise RuntimeError(
                f"Fim não encontrado para {begin}"
            )

    return start, finish, source[start:finish]


def replace_section(
    source,
    begin,
    end,
    mutator):

    start, finish, section = section_between(
        source,
        begin,
        end
    )

    section = mutator(section)

    return (
        source[:start]
        + section
        + source[finish:]
    )


# ------------------------------------------------------------
# BG1
# ------------------------------------------------------------

def patch_bg1(section):

    section = replace_once(
        section,
        '''    for (std::uint32_t screen_y = 0; screen_y < target.height(); ++screen_y) {
        const auto sample_y = mosaic_coordinate(
''',
        '''    for (std::uint32_t screen_y = 0; screen_y < target.height(); ++screen_y) {
        auto* const target_row =
            target.row_data(screen_y);

        const auto sample_y = mosaic_coordinate(
''',
        "BG1 direct framebuffer row"
    )

    section = replace_once(
        section,
        '''        const auto final_x = extend_horizontal ? target.width()
            : std::min(target.width(), static_cast<std::uint32_t>(
                std::max(horizontal_origin + 256 - inset, 0)));
        for (auto screen_x = first_x; screen_x < final_x; ++screen_x) {
''',
        '''        const auto final_x = extend_horizontal ? target.width()
            : std::min(target.width(), static_cast<std::uint32_t>(
                std::max(horizontal_origin + 256 - inset, 0)));

        TileRow cached_pixels{};
        std::uint16_t cached_tile{};
        std::uint32_t cached_tile_x{};
        std::uint32_t cached_tile_y{};
        std::uint32_t cached_pixel_y{8U};
        bool cached_tile_valid{};
        bool cached_priority_selected{};

        for (auto screen_x = first_x; screen_x < final_x; ++screen_x) {
''',
        "BG1 scanline tile cache"
    )

    old = '''            const auto tile_x = static_cast<std::uint32_t>(source_x) >> 3U;
            const auto page = (tile_x >> 5U) + (tile_y >> 5U) * pages_wide;
            const auto entry = page * 0x400U
                + (tile_y & 31U) * 32U + (tile_x & 31U);
            const auto tile = vram_word(ppu,
                static_cast<std::uint32_t>(ppu.bg1_screen_base) + entry);
            if (!selected_priority(tile, priority)) continue;
            const auto pixel_x = static_cast<std::uint32_t>(source_x) & 7U;
            const auto pixel_y = static_cast<std::uint32_t>(source_y) & 7U;
            const auto colour = ppu.background_mode == 3U
                ? tile_pixel_8bpp(ppu, ppu.bg1_character_base, tile,
                    pixel_x, pixel_y)
                : tile_pixel_4bpp(ppu, ppu.bg1_character_base, tile,
                    pixel_x, pixel_y);
'''

    new = '''            const auto tile_x =
                static_cast<std::uint32_t>(
                    source_x) >> 3U;

            const auto pixel_x =
                static_cast<std::uint32_t>(
                    source_x) & 7U;

            const auto pixel_y =
                static_cast<std::uint32_t>(
                    source_y) & 7U;

            if (!cached_tile_valid
                || cached_tile_x != tile_x
                || cached_tile_y != tile_y) {

                const auto page =
                    (tile_x >> 5U)
                    + (tile_y >> 5U)
                        * pages_wide;

                const auto entry =
                    page * 0x400U
                    + (tile_y & 31U) * 32U
                    + (tile_x & 31U);

                cached_tile =
                    vram_word(
                        ppu,
                        static_cast<std::uint32_t>(
                            ppu.bg1_screen_base)
                            + entry);

                cached_tile_x = tile_x;
                cached_tile_y = tile_y;
                cached_pixel_y = 8U;
                cached_tile_valid = true;

                cached_priority_selected =
                    selected_priority(
                        cached_tile,
                        priority);
            }

            if (!cached_priority_selected) {
                continue;
            }

            if (cached_pixel_y != pixel_y) {

                cached_pixels =
                    ppu.background_mode == 3U
                    ? decode_tile_row_8bpp(
                        ppu,
                        ppu.bg1_character_base,
                        cached_tile,
                        pixel_y)
                    : decode_tile_row_4bpp(
                        ppu,
                        ppu.bg1_character_base,
                        cached_tile,
                        pixel_y);

                cached_pixel_y = pixel_y;
            }

            const auto tile =
                cached_tile;

            const auto colour =
                cached_pixels[pixel_x];
'''

    section = replace_once(
        section,
        old,
        new,
        "BG1 cached tile lookup"
    )

    section = replace_once(
        section,
        '''                target.set(static_cast<std::int32_t>(screen_x),
                    static_cast<std::int32_t>(screen_y),
                    ppu.background_mode == 3U ? colour
                        : static_cast<std::uint8_t>(
                            ((tile >> 10U) & 7U) * 16U + colour));
''',
        '''                target_row[screen_x] =
                    ppu.background_mode == 3U
                        ? colour
                        : static_cast<std::uint8_t>(
                            ((tile >> 10U) & 7U)
                                * 16U
                            + colour);
''',
        "BG1 direct pixel store"
    )

    return section


text = replace_section(
    text,
    "void BackgroundRenderer::draw_bg1(",
    "void BackgroundRenderer::draw_bg2(",
    patch_bg1
)


# ------------------------------------------------------------
# BG2
# ------------------------------------------------------------

def patch_bg2(section):

    section = replace_once(
        section,
        '''    for (std::uint32_t screen_y = 0; screen_y < target.height(); ++screen_y) {
        const auto sample_y = mosaic_coordinate(
''',
        '''    for (std::uint32_t screen_y = 0; screen_y < target.height(); ++screen_y) {
        auto* const target_row =
            target.row_data(screen_y);

        const auto sample_y = mosaic_coordinate(
''',
        "BG2 direct framebuffer row"
    )

    section = replace_once(
        section,
        '''            ? static_cast<std::int32_t>(ppu.bg2_horizontal_offsets[
                static_cast<std::size_t>(sample_y)])
            : scroll_x;
        for (auto screen_x = first_x; screen_x < final_x; ++screen_x) {
''',
        '''            ? static_cast<std::int32_t>(ppu.bg2_horizontal_offsets[
                static_cast<std::size_t>(sample_y)])
            : scroll_x;

        TileRow cached_pixels{};
        std::uint16_t cached_tile{};
        std::uint32_t cached_tile_x{};
        std::uint32_t cached_tile_y{};
        std::uint32_t cached_pixel_y{8U};
        bool cached_tile_valid{};
        bool cached_priority_selected{};

        for (auto screen_x = first_x; screen_x < final_x; ++screen_x) {
''',
        "BG2 scanline tile cache"
    )

    old = '''            const auto tile_x = static_cast<std::uint32_t>(source_x) >> 3U;
            const auto page = (tile_x >> 5U) + (tile_y >> 5U) * pages_wide;
            const auto entry = page * 0x400U
                + (tile_y & 31U) * 32U + (tile_x & 31U);
            const auto tile = vram_word(ppu,
                static_cast<std::uint32_t>(ppu.bg2_screen_base) + entry);
            if (!selected_priority(tile, priority)) {
                if (!last_opaque_ground.empty() && screen_y >= 144U) {
                    const auto ground = last_opaque_ground[screen_x - first_x];
                    if (ground != 0U) {
                        target.set(static_cast<std::int32_t>(screen_x),
                            static_cast<std::int32_t>(screen_y), ground);
                    }
                }
                continue;
            }
            auto colour = tile_pixel_4bpp(ppu, ppu.bg2_character_base, tile,
                static_cast<std::uint32_t>(source_x) & 7U,
                static_cast<std::uint32_t>(source_y) & 7U);
'''

    new = '''            const auto tile_x =
                static_cast<std::uint32_t>(
                    source_x) >> 3U;

            const auto pixel_x =
                static_cast<std::uint32_t>(
                    source_x) & 7U;

            const auto pixel_y =
                static_cast<std::uint32_t>(
                    source_y) & 7U;

            if (!cached_tile_valid
                || cached_tile_x != tile_x
                || cached_tile_y != tile_y) {

                const auto page =
                    (tile_x >> 5U)
                    + (tile_y >> 5U)
                        * pages_wide;

                const auto entry =
                    page * 0x400U
                    + (tile_y & 31U) * 32U
                    + (tile_x & 31U);

                cached_tile =
                    vram_word(
                        ppu,
                        static_cast<std::uint32_t>(
                            ppu.bg2_screen_base)
                            + entry);

                cached_tile_x = tile_x;
                cached_tile_y = tile_y;
                cached_pixel_y = 8U;
                cached_tile_valid = true;

                cached_priority_selected =
                    selected_priority(
                        cached_tile,
                        priority);
            }

            if (!cached_priority_selected) {

                if (!last_opaque_ground.empty()
                    && screen_y >= 144U) {

                    const auto ground =
                        last_opaque_ground[
                            screen_x - first_x];

                    if (ground != 0U) {
                        target_row[screen_x] =
                            ground;
                    }
                }

                continue;
            }

            if (cached_pixel_y != pixel_y) {

                cached_pixels =
                    decode_tile_row_4bpp(
                        ppu,
                        ppu.bg2_character_base,
                        cached_tile,
                        pixel_y);

                cached_pixel_y =
                    pixel_y;
            }

            const auto tile =
                cached_tile;

            auto colour =
                cached_pixels[pixel_x];
'''

    section = replace_once(
        section,
        old,
        new,
        "BG2 cached tile lookup"
    )

    section = replace_once(
        section,
        '''                    target.set(static_cast<std::int32_t>(screen_x),
                        static_cast<std::int32_t>(screen_y), ground);
''',
        '''                    target_row[screen_x] =
                        ground;
''',
        "BG2 direct ground continuation"
    )

    section = replace_once(
        section,
        '''                target.set(static_cast<std::int32_t>(screen_x),
                    static_cast<std::int32_t>(screen_y), indexed_colour);
''',
        '''                target_row[screen_x] =
                    indexed_colour;
''',
        "BG2 direct indexed store"
    )

    return section


text = replace_section(
    text,
    "void BackgroundRenderer::draw_bg2(",
    "void BackgroundRenderer::draw_bg3(",
    patch_bg2
)


# ------------------------------------------------------------
# BG3
# ------------------------------------------------------------

def patch_bg3(section):

    section = replace_once(
        section,
        '''    for (std::uint32_t screen_y = 0; screen_y < target.height(); ++screen_y) {
        const auto sample_y = mosaic_coordinate(
''',
        '''    for (std::uint32_t screen_y = 0; screen_y < target.height(); ++screen_y) {
        auto* const target_row =
            target.row_data(screen_y);

        const auto sample_y = mosaic_coordinate(
''',
        "BG3 direct framebuffer row"
    )

    section = replace_once(
        section,
        '''        const auto final_x = extend_horizontal ? target.width()
            : std::min(target.width(), static_cast<std::uint32_t>(
                std::max(horizontal_origin + 256, 0)));
        for (auto screen_x = first_x; screen_x < final_x; ++screen_x) {
''',
        '''        const auto final_x = extend_horizontal ? target.width()
            : std::min(target.width(), static_cast<std::uint32_t>(
                std::max(horizontal_origin + 256, 0)));

        TileRow cached_pixels{};
        std::uint16_t cached_tile{};
        std::uint32_t cached_tile_x{};
        std::uint32_t cached_tile_y{};
        std::uint32_t cached_pixel_y{8U};
        bool cached_tile_valid{};
        bool cached_priority_selected{};

        for (auto screen_x = first_x; screen_x < final_x; ++screen_x) {
''',
        "BG3 scanline tile cache"
    )

    old = '''            const auto tile_x = static_cast<std::uint32_t>(source_x) >> 3U;
            const auto page = (tile_x >> 5U) + (tile_y >> 5U) * pages_wide;
            const auto entry = page * 0x400U
                + (tile_y & 31U) * 32U + (tile_x & 31U);
            const auto tile = vram_word(ppu,
                static_cast<std::uint32_t>(ppu.bg3_screen_base) + entry);
            if (!selected_priority(tile, priority)) continue;
            const auto colour = tile_pixel_2bpp(ppu, ppu.bg3_character_base, tile,
                static_cast<std::uint32_t>(source_x) & 7U,
                static_cast<std::uint32_t>(source_y) & 7U);
'''

    new = '''            const auto tile_x =
                static_cast<std::uint32_t>(
                    source_x) >> 3U;

            const auto pixel_x =
                static_cast<std::uint32_t>(
                    source_x) & 7U;

            const auto pixel_y =
                static_cast<std::uint32_t>(
                    source_y) & 7U;

            if (!cached_tile_valid
                || cached_tile_x != tile_x
                || cached_tile_y != tile_y) {

                const auto page =
                    (tile_x >> 5U)
                    + (tile_y >> 5U)
                        * pages_wide;

                const auto entry =
                    page * 0x400U
                    + (tile_y & 31U) * 32U
                    + (tile_x & 31U);

                cached_tile =
                    vram_word(
                        ppu,
                        static_cast<std::uint32_t>(
                            ppu.bg3_screen_base)
                            + entry);

                cached_tile_x = tile_x;
                cached_tile_y = tile_y;
                cached_pixel_y = 8U;
                cached_tile_valid = true;

                cached_priority_selected =
                    selected_priority(
                        cached_tile,
                        priority);
            }

            if (!cached_priority_selected) {
                continue;
            }

            if (cached_pixel_y != pixel_y) {

                cached_pixels =
                    decode_tile_row_2bpp(
                        ppu,
                        ppu.bg3_character_base,
                        cached_tile,
                        pixel_y);

                cached_pixel_y =
                    pixel_y;
            }

            const auto tile =
                cached_tile;

            const auto colour =
                cached_pixels[pixel_x];
'''

    section = replace_once(
        section,
        old,
        new,
        "BG3 cached tile lookup"
    )

    section = replace_once(
        section,
        '''            target.set(static_cast<std::int32_t>(screen_x),
                static_cast<std::int32_t>(screen_y),
                static_cast<std::uint8_t>(palette * 4U + colour));
''',
        '''            target_row[screen_x] =
                static_cast<std::uint8_t>(
                    palette * 4U + colour);
''',
        "BG3 direct indexed store"
    )

    return section


text = replace_section(
    text,
    "void BackgroundRenderer::draw_bg3(",
    "} // namespace starfox::render",
    patch_bg3
)

path.write_text(text, encoding="utf-8")


# ============================================================
# 3. SWITCH LINK-TIME OPTIMIZATION
# ============================================================

path = root / "ports/switch/CMakeLists.txt"
text = path.read_text(encoding="utf-8")

anchor = '''target_link_libraries(starfox_switch PRIVATE starfox_core SDL3::SDL3)
'''

addition = '''target_link_libraries(starfox_switch PRIVATE starfox_core SDL3::SDL3)

# The Switch runtime spends most of its time in the software SNES/Super FX
# presentation path. Enable whole-program optimisation for project-owned code
# in Release builds; prebuilt SDL/libnx libraries remain ordinary link inputs.
include(CheckIPOSupported)

check_ipo_supported(
    RESULT STARFOX_SWITCH_IPO_SUPPORTED
    OUTPUT STARFOX_SWITCH_IPO_ERROR
    LANGUAGES CXX)

if(STARFOX_SWITCH_IPO_SUPPORTED)
    set_property(
        TARGET starfox_core
        PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

    set_property(
        TARGET starfox_switch
        PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

    message(STATUS
        "Star Fox Switch: interprocedural optimisation enabled")
else()
    message(STATUS
        "Star Fox Switch: IPO unavailable: ${STARFOX_SWITCH_IPO_ERROR}")
endif()
'''

if addition not in text:
    if anchor not in text:
        raise RuntimeError(
            "target_link_libraries(starfox_switch) não encontrado"
        )

    text = text.replace(
        anchor,
        addition,
        1
    )

    print("PATCH   Switch IPO/LTO")
else:
    print("JA OK   Switch IPO/LTO")

path.write_text(text, encoding="utf-8")


print()
print("Performance Pass 01 aplicado.")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO DE FORMATAÇÃO"
echo "============================================================"

git diff --check

echo
echo "============================================================"
echo "DIFF"
echo "============================================================"

git diff \
    --stat \
    include/starfox/render/framebuffer.hpp \
    src/render/background_renderer.cpp \
    ports/switch/CMakeLists.txt

echo
echo "============================================================"
echo "BUILD + TESTES DESKTOP"
echo "============================================================"

cmake \
    -S . \
    -B "$BUILD_DESKTOP" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_BUILD_SWITCH=OFF

cmake \
    --build "$BUILD_DESKTOP" \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-desktop.log"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest.log"

echo
echo "============================================================"
echo "BUILD NINTENDO SWITCH"
echo "============================================================"

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

"$DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake" \
    -S . \
    -B "$BUILD_SWITCH" \
    -DSTARFOX_BUILD_RUNTIME=OFF \
    -DSTARFOX_BUILD_TESTS=OFF \
    -DSTARFOX_BUILD_SWITCH=ON \
    -DCMAKE_BUILD_TYPE=Release

cmake \
    --build "$BUILD_SWITCH" \
    --target starfox_switch_nro \
    -j"$(nproc)" \
    --verbose \
    2>&1 \
    | tee "$REPORT_DIR/build-switch.log"

NRO="$BUILD_SWITCH/ports/switch/starfox_switch.nro"

echo
echo "============================================================"
echo "NRO"
echo "============================================================"

test -s "$NRO"

ls -lh "$NRO"

grep -aob \
    'NRO0\|ASET' \
    "$NRO"

sha256sum \
    "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"

echo
echo "Otimizações aplicadas:"
echo "  [1] cache de scanline de tiles SNES"
echo "  [2] cache de entrada do tilemap"
echo "  [3] escrita direta no framebuffer"
echo "  [4] LTO/IPO no runtime Switch"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "IMPORTANTE:"
echo "  ainda NÃO foi criado commit."
echo "  primeiro valide o FPS no Ryujinx."
echo
echo "Status Git:"
git status --short

{
    echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 01"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "DIFF:"
    git diff --stat
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
