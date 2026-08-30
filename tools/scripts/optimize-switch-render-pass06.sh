#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf06-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass06/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 06"
echo "BG1 TILE-RUN FAST PATH + BG3 LOW/HIGH CACHE"
echo "============================================================"
echo

FILES=(
    include/starfox/render/background_renderer.hpp
    src/render/background_renderer.cpp
)

for file in "${FILES[@]}"
do
    test -f "$file" || {
        echo "ERRO: arquivo ausente:"
        echo "  $file"
        exit 10
    }

    mkdir -p \
        "$REPORT_DIR/backup/$(dirname "$file")"

    cp -a \
        "$file" \
        "$REPORT_DIR/backup/$file"
done

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])


# ============================================================
# PRÉ-REQUISITOS
# ============================================================

source_path = root / "src/render/background_renderer.cpp"
header_path = root / "include/starfox/render/background_renderer.hpp"

source = source_path.read_text(encoding="utf-8")
header = header_path.read_text(encoding="utf-8")

required = [
    "decode_tile_row_4bpp(",
    "decode_tile_row_2bpp(",
    "decode_tile_row_8bpp(",
    "Bucket::bg1",
    "Bucket::bg3",
    "Bg2PriorityCache",
]

for token in required:
    if token not in source and token not in header:
        raise RuntimeError(
            f"Pré-requisito ausente: {token}"
        )

print("PASS 01/04/05 detectadas.")


# ============================================================
# HEADER — BG3 CACHE
# ============================================================

if "struct Bg3PriorityCache" not in header:

    old = '''    mutable Bg2PriorityCache bg2_priority_cache_;
};
'''

    new = '''    mutable Bg2PriorityCache bg2_priority_cache_;

    struct Bg3PriorityCache {
        std::vector<std::uint8_t> low;
        std::vector<std::uint8_t> high;
        std::vector<std::uint8_t> all;

        std::uint32_t width{};
        std::uint32_t height{};

        std::uint32_t first_x{};
        std::uint32_t final_x{};

        std::int32_t horizontal_origin{};
        std::int32_t scroll_x{};
        std::int32_t scroll_y{};

        std::uint16_t screen_base{};
        std::uint16_t character_base{};

        std::uint8_t screen_size{};
        std::uint8_t mosaic{};
        std::uint8_t main_screen{};

        bool extend_horizontal{};
        bool ready_for_high{};
    };

    mutable Bg3PriorityCache bg3_priority_cache_;
};
'''

    if old not in header:
        raise RuntimeError(
            "Ponto de inserção do Bg3PriorityCache não encontrado."
        )

    header = header.replace(
        old,
        new,
        1
    )

    print("PATCH   Bg3PriorityCache")

else:
    print("JA OK   Bg3PriorityCache")

header_path.write_text(
    header,
    encoding="utf-8"
)


# ============================================================
# BG1
#
# Fast path:
#   sem mosaic horizontal
#
# Em vez de:
#   pixel -> tilemap -> VRAM -> pixel
#
# Fazemos:
#   tile -> decode 8 pixels -> escreve run
# ============================================================

source = source_path.read_text(
    encoding="utf-8"
)

start = source.find(
    "void BackgroundRenderer::draw_bg1("
)

end = source.find(
    "\nvoid BackgroundRenderer::draw_bg2(",
    start
)

if start < 0 or end < 0:
    raise RuntimeError(
        "draw_bg1 não encontrado"
    )


new_bg1 = r'''void BackgroundRenderer::draw_bg1(
    const simulation::SnesPpuState& ppu,
    Framebuffer& target,
    TilePriorityPass priority,
    std::int32_t horizontal_origin,
    bool extend_horizontal,
    std::uint32_t horizontal_inset) const noexcept {

    starfox::app::perf::ScopedTimer
        perf_timer_bg1{
            starfox::app::perf::Bucket::bg1};

    if ((ppu.main_screen & 0x01U) == 0U
        || (ppu.background_mode != 1U
            && ppu.background_mode != 2U
            && ppu.background_mode != 3U)) {

        return;
    }

    const auto width_tiles =
        (ppu.bg1_screen_size & 1U) != 0U
        ? 64U
        : 32U;

    const auto height_tiles =
        (ppu.bg1_screen_size & 2U) != 0U
        ? 64U
        : 32U;

    const auto pages_wide =
        width_tiles / 32U;

    const auto width_pixels =
        static_cast<std::int32_t>(
            width_tiles * 8U);

    const auto height_pixels =
        static_cast<std::int32_t>(
            height_tiles * 8U);

    const auto wrap =
        [](std::int32_t value,
           std::int32_t modulus) {

            value %= modulus;

            return value < 0
                ? value + modulus
                : value;
        };

    const auto inset =
        static_cast<std::int32_t>(
            std::min(
                horizontal_inset,
                128U));

    const auto first_x =
        extend_horizontal
        ? 0U
        : static_cast<std::uint32_t>(
            std::max(
                horizontal_origin + inset,
                0));

    const auto final_x =
        extend_horizontal
        ? target.width()
        : std::min(
            target.width(),
            static_cast<std::uint32_t>(
                std::max(
                    horizontal_origin
                        + 256
                        - inset,
                    0)));

    const auto mosaic_enabled =
        (ppu.mosaic & 0x01U) != 0U;


    for (std::uint32_t screen_y = 0U;
         screen_y < target.height();
         ++screen_y) {

        auto* const target_row =
            target.row_data(
                screen_y);

        const auto sample_y =
            mosaic_coordinate(
                static_cast<std::int32_t>(
                    screen_y),
                ppu.mosaic,
                0x01U);

        const auto source_y =
            wrap(
                sample_y
                    + ppu.bg1_scroll_y,
                height_pixels);

        const auto tile_y =
            static_cast<std::uint32_t>(
                source_y)
            >> 3U;

        const auto pixel_y =
            static_cast<std::uint32_t>(
                source_y)
            & 7U;


        // ====================================================
        // FAST PATH
        // ====================================================

        if (!mosaic_enabled) {

            auto screen_x =
                first_x;

            while (screen_x < final_x) {

                const auto logical_x =
                    static_cast<std::int32_t>(
                        screen_x)
                    - horizontal_origin;

                const auto source_x =
                    wrap(
                        logical_x
                            + ppu.bg1_scroll_x,
                        width_pixels);

                const auto tile_x =
                    static_cast<std::uint32_t>(
                        source_x)
                    >> 3U;

                const auto pixel_x =
                    static_cast<std::uint32_t>(
                        source_x)
                    & 7U;

                const auto page =
                    (tile_x >> 5U)
                    + (tile_y >> 5U)
                        * pages_wide;

                const auto entry =
                    page * 0x400U
                    + (tile_y & 31U) * 32U
                    + (tile_x & 31U);

                const auto tile =
                    vram_word(
                        ppu,
                        static_cast<std::uint32_t>(
                            ppu.bg1_screen_base)
                            + entry);

                const auto run =
                    std::min<std::uint32_t>(
                        8U - pixel_x,
                        final_x - screen_x);

                if (selected_priority(
                        tile,
                        priority)) {

                    const auto pixels =
                        ppu.background_mode == 3U
                        ? decode_tile_row_8bpp(
                            ppu,
                            ppu.bg1_character_base,
                            tile,
                            pixel_y)
                        : decode_tile_row_4bpp(
                            ppu,
                            ppu.bg1_character_base,
                            tile,
                            pixel_y);

                    const auto palette_base =
                        static_cast<std::uint8_t>(
                            ((tile >> 10U)
                                & 7U)
                            * 16U);

                    for (std::uint32_t offset = 0U;
                         offset < run;
                         ++offset) {

                        const auto colour =
                            pixels[
                                pixel_x
                                + offset];

                        if (colour == 0U) {
                            continue;
                        }

                        target_row[
                            screen_x
                            + offset] =
                            ppu.background_mode == 3U
                            ? colour
                            : static_cast<std::uint8_t>(
                                palette_base
                                + colour);
                    }
                }

                screen_x +=
                    run;
            }

            continue;
        }


        // ====================================================
        // MOSAIC FALLBACK
        // ====================================================

        TileRow cached_pixels{};

        std::uint16_t cached_tile{};

        std::uint32_t cached_tile_x{};
        std::uint32_t cached_pixel_y{8U};

        bool cached_valid{};
        bool cached_selected{};


        for (auto screen_x = first_x;
             screen_x < final_x;
             ++screen_x) {

            const auto logical_x =
                static_cast<std::int32_t>(
                    screen_x)
                - horizontal_origin;

            const auto sample_x =
                mosaic_coordinate(
                    logical_x,
                    ppu.mosaic,
                    0x01U);

            const auto source_x =
                wrap(
                    sample_x
                        + ppu.bg1_scroll_x,
                    width_pixels);

            const auto tile_x =
                static_cast<std::uint32_t>(
                    source_x)
                >> 3U;

            const auto pixel_x =
                static_cast<std::uint32_t>(
                    source_x)
                & 7U;

            if (!cached_valid
                || cached_tile_x != tile_x) {

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

                cached_tile_x =
                    tile_x;

                cached_pixel_y =
                    8U;

                cached_valid =
                    true;

                cached_selected =
                    selected_priority(
                        cached_tile,
                        priority);
            }

            if (!cached_selected) {
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

                cached_pixel_y =
                    pixel_y;
            }

            const auto colour =
                cached_pixels[
                    pixel_x];

            if (colour == 0U) {
                continue;
            }

            target_row[
                screen_x] =
                ppu.background_mode == 3U
                ? colour
                : static_cast<std::uint8_t>(
                    ((cached_tile >> 10U)
                        & 7U)
                        * 16U
                    + colour);
        }
    }
}
'''

source = (
    source[:start]
    + new_bg1
    + source[end:]
)

print(
    "PATCH   BG1 tile-run fast path"
)


# ============================================================
# BG3
#
# LOW:
#   decodifica uma vez
#   gera LOW + HIGH + ALL
#
# HIGH:
#   apenas reaplica cache
# ============================================================

start = source.find(
    "void BackgroundRenderer::draw_bg3("
)

end = source.find(
    "\n} // namespace starfox::render",
    start
)

if start < 0 or end < 0:
    raise RuntimeError(
        "draw_bg3 não encontrado"
    )


new_bg3 = r'''void BackgroundRenderer::draw_bg3(
    const simulation::SnesPpuState& ppu,
    Framebuffer& target,
    TilePriorityPass priority,
    std::int32_t horizontal_origin,
    bool extend_horizontal) const noexcept {

    starfox::app::perf::ScopedTimer
        perf_timer_bg3{
            starfox::app::perf::Bucket::bg3};

    if ((ppu.main_screen & 0x04U) == 0U) {

        bg3_priority_cache_.ready_for_high =
            false;

        return;
    }


    const auto width_tiles =
        (ppu.bg3_screen_size & 1U) != 0U
        ? 64U
        : 32U;

    const auto height_tiles =
        (ppu.bg3_screen_size & 2U) != 0U
        ? 64U
        : 32U;

    const auto pages_wide =
        width_tiles / 32U;

    const auto width_pixels =
        static_cast<std::int32_t>(
            width_tiles * 8U);

    const auto height_pixels =
        static_cast<std::int32_t>(
            height_tiles * 8U);

    const auto wrap =
        [](std::int32_t value,
           std::int32_t modulus) {

            value %= modulus;

            return value < 0
                ? value + modulus
                : value;
        };


    const auto first_x =
        extend_horizontal
        ? 0U
        : static_cast<std::uint32_t>(
            std::max(
                horizontal_origin,
                0));

    const auto final_x =
        extend_horizontal
        ? target.width()
        : std::min(
            target.width(),
            static_cast<std::uint32_t>(
                std::max(
                    horizontal_origin
                        + 256,
                    0)));


    auto& cache =
        bg3_priority_cache_;


    const auto cache_matches =
        cache.width == target.width()
        && cache.height == target.height()
        && cache.first_x == first_x
        && cache.final_x == final_x
        && cache.horizontal_origin
            == horizontal_origin
        && cache.scroll_x
            == ppu.bg3_scroll_x
        && cache.scroll_y
            == ppu.bg3_scroll_y
        && cache.screen_base
            == ppu.bg3_screen_base
        && cache.character_base
            == ppu.bg3_character_base
        && cache.screen_size
            == ppu.bg3_screen_size
        && cache.mosaic
            == ppu.mosaic
        && cache.main_screen
            == ppu.main_screen
        && cache.extend_horizontal
            == extend_horizontal;


    // ========================================================
    // SECOND PRIORITY PASS
    // ========================================================

    if (priority == TilePriorityPass::high
        && cache.ready_for_high
        && cache_matches) {

        for (std::uint32_t y = 0U;
             y < target.height();
             ++y) {

            const auto* source_row =
                cache.high.data()
                + static_cast<std::size_t>(
                    y)
                    * target.width();

            auto* target_row =
                target.row_data(
                    y);

            for (auto x = first_x;
                 x < final_x;
                 ++x) {

                const auto colour =
                    source_row[x];

                if (colour != 0U) {
                    target_row[x] =
                        colour;
                }
            }
        }

        cache.ready_for_high =
            false;

        return;
    }


    cache.width =
        target.width();

    cache.height =
        target.height();

    cache.first_x =
        first_x;

    cache.final_x =
        final_x;

    cache.horizontal_origin =
        horizontal_origin;

    cache.scroll_x =
        ppu.bg3_scroll_x;

    cache.scroll_y =
        ppu.bg3_scroll_y;

    cache.screen_base =
        ppu.bg3_screen_base;

    cache.character_base =
        ppu.bg3_character_base;

    cache.screen_size =
        ppu.bg3_screen_size;

    cache.mosaic =
        ppu.mosaic;

    cache.main_screen =
        ppu.main_screen;

    cache.extend_horizontal =
        extend_horizontal;

    cache.ready_for_high =
        false;


    const auto pixel_count =
        static_cast<std::size_t>(
            target.width())
        * target.height();


    const auto prepare =
        [pixel_count](
            std::vector<std::uint8_t>& layer) {

            if (layer.size()
                != pixel_count) {

                layer.resize(
                    pixel_count);
            }

            std::fill(
                layer.begin(),
                layer.end(),
                0U);
        };


    prepare(cache.low);
    prepare(cache.high);
    prepare(cache.all);


    const auto mosaic_enabled =
        (ppu.mosaic & 0x04U) != 0U;


    for (std::uint32_t screen_y = 0U;
         screen_y < target.height();
         ++screen_y) {

        const auto sample_y =
            mosaic_coordinate(
                static_cast<std::int32_t>(
                    screen_y),
                ppu.mosaic,
                0x04U);

        const auto source_y =
            wrap(
                sample_y
                    + ppu.bg3_scroll_y,
                height_pixels);

        const auto tile_y =
            static_cast<std::uint32_t>(
                source_y)
            >> 3U;

        const auto pixel_y =
            static_cast<std::uint32_t>(
                source_y)
            & 7U;

        const auto row_index =
            static_cast<std::size_t>(
                screen_y)
            * target.width();


        // ====================================================
        // TILE-RUN FAST PATH
        // ====================================================

        if (!mosaic_enabled) {

            auto screen_x =
                first_x;

            while (screen_x < final_x) {

                const auto logical_x =
                    static_cast<std::int32_t>(
                        screen_x)
                    - horizontal_origin;

                const auto source_x =
                    wrap(
                        logical_x
                            + ppu.bg3_scroll_x,
                        width_pixels);

                const auto tile_x =
                    static_cast<std::uint32_t>(
                        source_x)
                    >> 3U;

                const auto pixel_x =
                    static_cast<std::uint32_t>(
                        source_x)
                    & 7U;

                const auto page =
                    (tile_x >> 5U)
                    + (tile_y >> 5U)
                        * pages_wide;

                const auto entry =
                    page * 0x400U
                    + (tile_y & 31U) * 32U
                    + (tile_x & 31U);

                const auto tile =
                    vram_word(
                        ppu,
                        static_cast<std::uint32_t>(
                            ppu.bg3_screen_base)
                            + entry);

                const auto pixels =
                    decode_tile_row_2bpp(
                        ppu,
                        ppu.bg3_character_base,
                        tile,
                        pixel_y);

                const auto palette_base =
                    static_cast<std::uint8_t>(
                        ((tile >> 10U)
                            & 7U)
                        * 4U);

                const auto high_priority =
                    (tile & 0x2000U)
                    != 0U;

                const auto run =
                    std::min<std::uint32_t>(
                        8U - pixel_x,
                        final_x - screen_x);

                for (std::uint32_t offset = 0U;
                     offset < run;
                     ++offset) {

                    const auto colour =
                        pixels[
                            pixel_x
                            + offset];

                    if (colour == 0U) {
                        continue;
                    }

                    const auto indexed =
                        static_cast<std::uint8_t>(
                            palette_base
                            + colour);

                    const auto index =
                        row_index
                        + screen_x
                        + offset;

                    cache.all[index] =
                        indexed;

                    if (high_priority) {
                        cache.high[index] =
                            indexed;
                    } else {
                        cache.low[index] =
                            indexed;
                    }
                }

                screen_x +=
                    run;
            }

            continue;
        }


        // ====================================================
        // MOSAIC PATH
        // ====================================================

        TileRow cached_pixels{};

        std::uint16_t cached_tile{};

        std::uint32_t cached_tile_x{};
        std::uint32_t cached_pixel_y{8U};

        bool cached_valid{};


        for (auto screen_x = first_x;
             screen_x < final_x;
             ++screen_x) {

            const auto logical_x =
                static_cast<std::int32_t>(
                    screen_x)
                - horizontal_origin;

            const auto sample_x =
                mosaic_coordinate(
                    logical_x,
                    ppu.mosaic,
                    0x04U);

            const auto source_x =
                wrap(
                    sample_x
                        + ppu.bg3_scroll_x,
                    width_pixels);

            const auto tile_x =
                static_cast<std::uint32_t>(
                    source_x)
                >> 3U;

            const auto pixel_x =
                static_cast<std::uint32_t>(
                    source_x)
                & 7U;

            if (!cached_valid
                || cached_tile_x != tile_x) {

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

                cached_tile_x =
                    tile_x;

                cached_pixel_y =
                    8U;

                cached_valid =
                    true;
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

            const auto colour =
                cached_pixels[
                    pixel_x];

            if (colour == 0U) {
                continue;
            }

            const auto indexed =
                static_cast<std::uint8_t>(
                    ((cached_tile >> 10U)
                        & 7U)
                        * 4U
                    + colour);

            const auto index =
                row_index
                + screen_x;

            cache.all[index] =
                indexed;

            if ((cached_tile
                    & 0x2000U)
                != 0U) {

                cache.high[index] =
                    indexed;

            } else {

                cache.low[index] =
                    indexed;
            }
        }
    }


    cache.ready_for_high =
        priority
        == TilePriorityPass::low;


    const std::vector<std::uint8_t>*
        layer = nullptr;


    switch (priority) {

    case TilePriorityPass::low:
        layer =
            &cache.low;
        break;

    case TilePriorityPass::high:
        layer =
            &cache.high;

        cache.ready_for_high =
            false;

        break;

    case TilePriorityPass::all:
    default:
        layer =
            &cache.all;

        cache.ready_for_high =
            false;

        break;
    }


    for (std::uint32_t y = 0U;
         y < target.height();
         ++y) {

        const auto* source_row =
            layer->data()
            + static_cast<std::size_t>(
                y)
                * target.width();

        auto* target_row =
            target.row_data(
                y);

        for (auto x = first_x;
             x < final_x;
             ++x) {

            const auto colour =
                source_row[x];

            if (colour != 0U) {
                target_row[x] =
                    colour;
            }
        }
    }
}
'''


source = (
    source[:start]
    + new_bg3
    + source[end:]
)

source_path.write_text(
    source,
    encoding="utf-8"
)

print(
    "PATCH   BG3 shared priority cache + tile-run"
)
PY

echo
echo "============================================================"
echo "VALIDAÇÃO DE CÓDIGO"
echo "============================================================"

git diff --check

echo
echo "BG1 fast path:"
grep -n \
    -A10 \
    'BG1' \
    src/render/background_renderer.cpp \
    | grep -A10 'FAST PATH' \
    | head -n 30 || true

echo
echo "BG3 cache:"
grep -R \
    -n \
    'Bg3PriorityCache\|ready_for_high\|TILE-RUN FAST PATH' \
    include/starfox/render/background_renderer.hpp \
    src/render/background_renderer.cpp \
    | head -n 80

echo
echo
git diff \
    --stat \
    include/starfox/render/background_renderer.hpp \
    src/render/background_renderer.cpp

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
echo "BUILD SWITCH"
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
echo "VALIDAÇÃO NRO"
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
echo "PASS 06 CONCLUÍDA"
echo "============================================================"

echo
echo "Otimizações:"
echo "  [✓] BG1 tile-run fast path"
echo "  [✓] BG3 tile-run fast path"
echo "  [✓] BG3 LOW/HIGH shared decode"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "Profiler:"
echo "  [SFE PERF2]"
echo
echo "IMPORTANTE:"
echo "  não foi criado commit."
echo "  teste SEM gravação de vídeo."
echo
echo "Git status:"
git status --short

{
    echo "STAR FOX ENHANCED — PERFORMANCE PASS 06"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Optimizations:"
    echo "  BG1 tile-run"
    echo "  BG3 tile-run"
    echo "  BG3 LOW/HIGH shared decode"
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
