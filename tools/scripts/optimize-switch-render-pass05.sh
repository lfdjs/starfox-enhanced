#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf05-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass05/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 05"
echo "BG2 LOW/HIGH PRIORITY DECODE CACHE"
echo "============================================================"
echo

FILES=(
    include/starfox/render/background_renderer.hpp
    src/render/background_renderer.cpp
)

for file in "${FILES[@]}"
do
    if [[ ! -f "$file" ]]
    then
        echo "ERRO: arquivo ausente:"
        echo "  $file"
        exit 10
    fi

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

root = Path(
    os.environ["PROJECT_ROOT"]
)


# ============================================================
# HEADER — CACHE PERSISTENTE ENTRE LOW -> HIGH
# ============================================================

path = root / "include/starfox/render/background_renderer.hpp"

text = path.read_text(
    encoding="utf-8"
)

if "#include <vector>" not in text:

    old = "#include <cstdint>\n"

    new = '''#include <cstdint>
#include <vector>
'''

    if old not in text:
        raise RuntimeError(
            "include <cstdint> não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   background_renderer.hpp: <vector>"
    )


marker = "struct Bg2PriorityCache"

if marker not in text:

    old = '''    void draw_bg3(
        const simulation::SnesPpuState& ppu,
        Framebuffer& target,
        TilePriorityPass priority = TilePriorityPass::all,
        std::int32_t horizontal_origin = 0,
        bool extend_horizontal = true) const noexcept;
};
'''

    new = '''    void draw_bg3(
        const simulation::SnesPpuState& ppu,
        Framebuffer& target,
        TilePriorityPass priority = TilePriorityPass::all,
        std::int32_t horizontal_origin = 0,
        bool extend_horizontal = true) const noexcept;

private:
    struct Bg2PriorityCache {
        std::vector<std::uint8_t> low;
        std::vector<std::uint8_t> high;
        std::vector<std::uint8_t> all;

        std::uint32_t width{};
        std::uint32_t height{};

        std::uint32_t first_x{};
        std::uint32_t final_x{};

        std::int32_t scroll_x{};
        std::int32_t scroll_y{};
        std::int32_t horizontal_origin{};

        bool extend_horizontal{};
        bool ready_for_high{};
    };

    mutable Bg2PriorityCache bg2_priority_cache_;
};
'''

    if old not in text:
        raise RuntimeError(
            "fim da classe BackgroundRenderer não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   BackgroundRenderer::Bg2PriorityCache"
    )

else:

    print(
        "JA OK   Bg2PriorityCache"
    )


path.write_text(
    text,
    encoding="utf-8"
)


# ============================================================
# SOURCE — substituir SOMENTE draw_bg2()
# ============================================================

path = root / "src/render/background_renderer.cpp"

text = path.read_text(
    encoding="utf-8"
)


# Pass 01 precisa estar presente.
if "decode_tile_row_4bpp(" not in text:
    raise RuntimeError(
        "Performance Pass 01 não detectada: "
        "decode_tile_row_4bpp ausente"
    )

if "row_data(" not in (
    root / "include/starfox/render/framebuffer.hpp"
).read_text(encoding="utf-8"):
    raise RuntimeError(
        "Framebuffer::row_data não encontrado"
    )


start = text.find(
    "void BackgroundRenderer::draw_bg2("
)

end = text.find(
    "\nvoid BackgroundRenderer::draw_bg3(",
    start
)

if start < 0 or end < 0:
    raise RuntimeError(
        "draw_bg2() não encontrado"
    )


new_function = r'''void BackgroundRenderer::draw_bg2(
    const simulation::SnesPpuState& ppu,
    std::int32_t scroll_x,
    std::int32_t scroll_y,
    Framebuffer& target,
    TilePriorityPass priority,
    std::int32_t horizontal_origin,
    bool extend_horizontal) const noexcept {

    starfox::app::perf::ScopedTimer
        perf_timer_bg2{
            starfox::app::perf::Bucket::bg2};

    if ((ppu.main_screen & 0x02U) == 0U) {
        bg2_priority_cache_.ready_for_high = false;
        return;
    }

    const auto width_tiles =
        (ppu.bg2_screen_size & 1U) != 0U
        ? 64U
        : 32U;

    const auto height_tiles =
        (ppu.bg2_screen_size & 2U) != 0U
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
                    horizontal_origin + 256,
                    0)));


    const auto cache_matches =
        bg2_priority_cache_.width
                == target.width()
        && bg2_priority_cache_.height
                == target.height()
        && bg2_priority_cache_.first_x
                == first_x
        && bg2_priority_cache_.final_x
                == final_x
        && bg2_priority_cache_.scroll_x
                == scroll_x
        && bg2_priority_cache_.scroll_y
                == scroll_y
        && bg2_priority_cache_.horizontal_origin
                == horizontal_origin
        && bg2_priority_cache_.extend_horizontal
                == extend_horizontal;


    // ========================================================
    // HIGH PRIORITY FAST PATH
    //
    // A normal renderer sequence is:
    //
    //     BG2 LOW
    //     OAM / geometry
    //     BG2 HIGH
    //
    // LOW already decoded every source pixel. Reuse the cached HIGH
    // layer instead of repeating all VRAM/tile/mosaic calculations.
    // ========================================================

    if (priority == TilePriorityPass::high
        && bg2_priority_cache_.ready_for_high
        && cache_matches) {

        const auto width =
            target.width();

        for (std::uint32_t screen_y = 0U;
             screen_y < target.height();
             ++screen_y) {

            const auto* source_row =
                bg2_priority_cache_.high.data()
                + static_cast<std::size_t>(
                    screen_y)
                    * width;

            auto* target_row =
                target.row_data(
                    screen_y);

            for (auto screen_x = first_x;
                 screen_x < final_x;
                 ++screen_x) {

                const auto colour =
                    source_row[screen_x];

                if (colour != 0U) {
                    target_row[screen_x] =
                        colour;
                }
            }
        }

        // A HIGH layer is paired with exactly one LOW build.
        // Prevent accidental reuse on a later frame.
        bg2_priority_cache_.ready_for_high =
            false;

        return;
    }


    // ========================================================
    // BUILD CACHE
    //
    // Build LOW, HIGH and ALL in one source traversal.
    // ========================================================

    auto& cache =
        bg2_priority_cache_;

    cache.width =
        target.width();

    cache.height =
        target.height();

    cache.first_x =
        first_x;

    cache.final_x =
        final_x;

    cache.scroll_x =
        scroll_x;

    cache.scroll_y =
        scroll_y;

    cache.horizontal_origin =
        horizontal_origin;

    cache.extend_horizontal =
        extend_horizontal;

    cache.ready_for_high =
        false;


    const auto pixel_count =
        static_cast<std::size_t>(
            target.width())
        * target.height();

    cache.low.assign(
        pixel_count,
        0U);

    cache.high.assign(
        pixel_count,
        0U);

    cache.all.assign(
        pixel_count,
        0U);


    // ========================================================
    // MODE 2 VERTICAL-OFFSET TABLE
    // ========================================================

    std::array<std::uint16_t, 32>
        vertical_offsets{};

    if (ppu.background_mode == 2U
        && ppu.bg2_vertical_offsets_enabled) {

        for (std::size_t index = 0U;
             index < vertical_offsets.size();
             ++index) {

            vertical_offsets[index] =
                vram_word(
                    ppu,
                    0x2fa0U
                    + static_cast<std::uint32_t>(
                        index));
        }
    }


    const auto vertical_value =
        [&vertical_offsets](
            std::size_t index) {

            return static_cast<std::int32_t>(
                vertical_offsets[index]
                & 0x1fffU);
        };


    const auto vertical_valid =
        [&vertical_offsets](
            std::size_t index) {

            return (
                vertical_offsets[index]
                & 0x4000U)
                != 0U;
        };


    const auto signed_difference =
        [](std::int32_t to,
           std::int32_t from) {

            auto difference =
                (to - from)
                & 0x1fff;

            if (difference > 4'095) {
                difference -= 8'192;
            }

            return difference;
        };


    auto first_valid =
        vertical_offsets.size();

    auto last_valid =
        vertical_offsets.size();


    for (std::size_t index = 0U;
         index < vertical_offsets.size();
         ++index) {

        if (!vertical_valid(index)) {
            continue;
        }

        if (first_valid
            == vertical_offsets.size()) {

            first_valid =
                index;
        }

        last_valid =
            index;
    }


    const auto extrapolated_delta =
        first_valid
                != vertical_offsets.size()
        && last_valid
                != first_valid

        ? signed_difference(
            vertical_value(last_valid),
            vertical_value(first_valid))

        : 0;


    const auto extrapolated_span =
        first_valid
                != vertical_offsets.size()
        && last_valid
                != first_valid

        ? static_cast<std::int32_t>(
            last_valid
            - first_valid)

        : 1;


    const auto expanded_mode2 =
        extend_horizontal
        && target.width() > 256U
        && ppu.background_mode == 2U
        && ppu.bg2_vertical_offsets_enabled;


    const auto extended_vertical_offset =
        [&vertical_value,
         &vertical_valid,
         extrapolated_delta,
         extrapolated_span,
         expanded_mode2](
            std::int32_t visible_column,
            std::int32_t fallback) {

            if (visible_column >= 1
                && visible_column <= 32) {

                const auto index =
                    static_cast<std::size_t>(
                        visible_column - 1);

                return vertical_valid(index)
                    ? vertical_value(index)
                    : fallback;
            }


            const auto wrap_offset =
                [](std::int32_t offset) {

                    offset %= 8'192;

                    return offset < 0
                        ? offset + 8'192
                        : offset;
                };


            const auto extend_slope =
                [extrapolated_delta,
                 extrapolated_span](
                    std::int32_t anchor,
                    std::int32_t distance) {

                    return anchor
                        + extrapolated_delta
                            * distance
                            / extrapolated_span;
                };


            if (visible_column <= 0
                && vertical_valid(0U)) {

                const auto distance =
                    expanded_mode2
                    ? visible_column - 1
                    : std::min(
                        visible_column + 1,
                        0);

                return wrap_offset(
                    extend_slope(
                        vertical_value(0U),
                        distance));
            }


            if (visible_column > 32
                && vertical_valid(31U)) {

                return wrap_offset(
                    extend_slope(
                        vertical_value(31U),
                        visible_column - 32));
            }


            return fallback;
        };


    const auto extend_ground_down =
        expanded_mode2
        && target.height() > 192U;


    std::vector<std::int32_t>
        column_scroll_y;


    if (ppu.background_mode == 2U
        && ppu.bg2_vertical_offsets_enabled) {

        column_scroll_y.resize(
            final_x - first_x,
            scroll_y);

        for (auto screen_x = first_x;
             screen_x < final_x;
             ++screen_x) {

            const auto logical_x =
                static_cast<std::int32_t>(
                    screen_x)
                - horizontal_origin;

            const auto column_coordinate =
                logical_x
                + (scroll_x & 7);

            const auto visible_column =
                column_coordinate >= 0
                ? column_coordinate / 8
                : -(
                    (-column_coordinate + 7)
                    / 8);

            column_scroll_y[
                screen_x - first_x] =
                extended_vertical_offset(
                    visible_column,
                    scroll_y);
        }
    }


    // Each priority pass needs its own continuation history because
    // Corneria's Mode 2 ground can occur in either priority.
    std::vector<std::uint8_t>
        low_ground;

    std::vector<std::uint8_t>
        high_ground;

    std::vector<std::uint8_t>
        all_ground;


    if (extend_ground_down) {

        const auto span =
            final_x - first_x;

        low_ground.assign(
            span,
            0U);

        high_ground.assign(
            span,
            0U);

        all_ground.assign(
            span,
            0U);
    }


    const auto target_width =
        target.width();


    // ========================================================
    // ONE COMPLETE BG2 DECODE
    // ========================================================

    for (std::uint32_t screen_y = 0U;
         screen_y < target.height();
         ++screen_y) {

        const auto sample_y =
            mosaic_coordinate(
                static_cast<std::int32_t>(
                    screen_y),
                ppu.mosaic,
                0x02U);


        const auto row_scroll_x =
            ppu.bg2_horizontal_offsets_enabled
            && sample_y >= 0
            && static_cast<std::size_t>(
                sample_y)
                < ppu.bg2_horizontal_offsets.size()

            ? static_cast<std::int32_t>(
                ppu.bg2_horizontal_offsets[
                    static_cast<std::size_t>(
                        sample_y)])

            : scroll_x;


        const auto cache_row =
            static_cast<std::size_t>(
                screen_y)
            * target_width;


        TileRow cached_pixels{};

        std::uint16_t cached_tile{};

        std::uint32_t cached_tile_x{};
        std::uint32_t cached_tile_y{};
        std::uint32_t cached_pixel_y{8U};

        bool cached_tile_valid{};


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
                    0x02U);


            const auto sampled_screen_x =
                std::clamp(
                    sample_x
                        + horizontal_origin,

                    static_cast<std::int32_t>(
                        first_x),

                    static_cast<std::int32_t>(
                        final_x - 1U));


            const auto current_scroll_y =
                column_scroll_y.empty()

                ? scroll_y

                : column_scroll_y[
                    static_cast<std::size_t>(
                        sampled_screen_x)
                    - first_x];


            const auto source_y =
                wrap(
                    sample_y
                        + current_scroll_y,
                    height_pixels);


            const auto tile_y =
                static_cast<std::uint32_t>(
                    source_y)
                >> 3U;


            const auto source_x =
                wrap(
                    sample_x
                        + row_scroll_x,
                    width_pixels);


            const auto tile_x =
                static_cast<std::uint32_t>(
                    source_x)
                >> 3U;


            const auto pixel_x =
                static_cast<std::uint32_t>(
                    source_x)
                & 7U;


            const auto pixel_y =
                static_cast<std::uint32_t>(
                    source_y)
                & 7U;


            if (!cached_tile_valid
                || cached_tile_x != tile_x
                || cached_tile_y != tile_y) {

                const auto page =
                    (tile_x >> 5U)
                    + (tile_y >> 5U)
                        * pages_wide;


                const auto entry =
                    page * 0x400U
                    + (tile_y & 31U)
                        * 32U
                    + (tile_x & 31U);


                cached_tile =
                    vram_word(
                        ppu,

                        static_cast<std::uint32_t>(
                            ppu.bg2_screen_base)
                        + entry);


                cached_tile_x =
                    tile_x;

                cached_tile_y =
                    tile_y;

                cached_pixel_y =
                    8U;

                cached_tile_valid =
                    true;
            }


            if (cached_pixel_y
                != pixel_y) {

                cached_pixels =
                    decode_tile_row_4bpp(
                        ppu,
                        ppu.bg2_character_base,
                        cached_tile,
                        pixel_y);

                cached_pixel_y =
                    pixel_y;
            }


            const auto colour =
                cached_pixels[
                    pixel_x];


            const auto palette =
                static_cast<std::uint8_t>(
                    (cached_tile >> 10U)
                    & 7U);


            const auto high_priority =
                (cached_tile
                    & 0x2000U)
                    != 0U;


            const auto column =
                screen_x - first_x;


            const auto cache_index =
                cache_row
                + screen_x;


            bool wrote_low{};
            bool wrote_high{};
            bool wrote_all{};


            if (colour != 0U) {

                const auto indexed_colour =
                    static_cast<std::uint8_t>(
                        palette * 16U
                        + colour);


                cache.all[
                    cache_index] =
                    indexed_colour;

                wrote_all =
                    true;


                if (high_priority) {

                    cache.high[
                        cache_index] =
                        indexed_colour;

                    wrote_high =
                        true;

                } else {

                    cache.low[
                        cache_index] =
                        indexed_colour;

                    wrote_low =
                        true;
                }


                if (extend_ground_down) {

                    all_ground[column] =
                        indexed_colour;

                    if (high_priority) {

                        high_ground[column] =
                            indexed_colour;

                    } else {

                        low_ground[column] =
                            indexed_colour;
                    }
                }
            }


            if (extend_ground_down
                && screen_y >= 144U) {

                if (!wrote_low
                    && low_ground[column]
                        != 0U) {

                    cache.low[
                        cache_index] =
                        low_ground[column];
                }


                if (!wrote_high
                    && high_ground[column]
                        != 0U) {

                    cache.high[
                        cache_index] =
                        high_ground[column];
                }


                if (!wrote_all
                    && all_ground[column]
                        != 0U) {

                    cache.all[
                        cache_index] =
                        all_ground[column];
                }
            }
        }
    }


    // LOW has produced the cache that HIGH may consume later.
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


    // ========================================================
    // APPLY SELECTED PRIORITY LAYER
    // ========================================================

    for (std::uint32_t screen_y = 0U;
         screen_y < target.height();
         ++screen_y) {

        const auto* source_row =
            layer->data()
            + static_cast<std::size_t>(
                screen_y)
                * target_width;


        auto* target_row =
            target.row_data(
                screen_y);


        for (auto screen_x = first_x;
             screen_x < final_x;
             ++screen_x) {

            const auto colour =
                source_row[
                    screen_x];


            if (colour != 0U) {

                target_row[
                    screen_x] =
                    colour;
            }
        }
    }
}
'''


text = (
    text[:start]
    + new_function
    + text[end:]
)

path.write_text(
    text,
    encoding="utf-8"
)

print(
    "PATCH   draw_bg2(): one decode for LOW + HIGH"
)
PY

echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check

echo
echo "Cache BG2:"
grep -R \
    -n \
    'Bg2PriorityCache\|ready_for_high\|HIGH PRIORITY FAST PATH' \
    include/starfox/render/background_renderer.hpp \
    src/render/background_renderer.cpp \
    | head -n 100

echo
echo
echo "Diff:"
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
echo "PERFORMANCE PASS 05 CONCLUÍDA"
echo "============================================================"

echo
echo "Otimização:"
echo "  LOW  = decodifica BG2 e gera LOW/HIGH/ALL"
echo "  HIGH = reutiliza a camada já decodificada"
echo
echo "Novo NRO:"
echo "  $NRO"
echo
echo "Profiler continua ativo:"
echo "  [SFE PERF2]"
echo
echo "IMPORTANTE:"
echo "  ainda NÃO foi criado commit."
echo
echo "Teste SEM captura de vídeo."
echo
echo "Git status:"
git status --short

{
    echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 05"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Optimization:"
    echo "  shared BG2 LOW/HIGH decode cache"
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
