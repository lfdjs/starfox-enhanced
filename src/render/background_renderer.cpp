#include "starfox/app/perf_profiler.hpp"
#include "starfox/render/background_renderer.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <vector>

namespace starfox::render {
namespace {

std::uint16_t vram_word(
    const simulation::SnesPpuState& ppu, std::uint32_t word_address) noexcept {
    const auto offset = (word_address & 0x7fffU) * 2U;
    return static_cast<std::uint16_t>(ppu.vram[offset])
        | (static_cast<std::uint16_t>(ppu.vram[offset + 1U]) << 8U);
}

[[maybe_unused]] std::uint8_t tile_pixel_4bpp(
    const simulation::SnesPpuState& ppu,
    std::uint16_t character_base,
    std::uint16_t tile,
    std::uint32_t x,
    std::uint32_t y) noexcept {
    if ((tile & 0x4000U) != 0U) x = 7U - x;
    if ((tile & 0x8000U) != 0U) y = 7U - y;
    const auto tile_number = static_cast<std::uint32_t>(tile & 0x03ffU);
    const auto base = (static_cast<std::uint32_t>(character_base) * 2U
        + tile_number * 32U + y * 2U) & 0xffffU;
    const auto plane01 = static_cast<std::uint16_t>(ppu.vram[base])
        | (static_cast<std::uint16_t>(ppu.vram[(base + 1U) & 0xffffU]) << 8U);
    const auto plane23 = static_cast<std::uint16_t>(ppu.vram[(base + 16U) & 0xffffU])
        | (static_cast<std::uint16_t>(ppu.vram[(base + 17U) & 0xffffU]) << 8U);
    const auto mask = static_cast<std::uint8_t>(0x80U >> x);
    return static_cast<std::uint8_t>(
        ((plane01 & mask) != 0U ? 1U : 0U)
        | ((plane01 & (static_cast<std::uint16_t>(mask) << 8U)) != 0U ? 2U : 0U)
        | ((plane23 & mask) != 0U ? 4U : 0U)
        | ((plane23 & (static_cast<std::uint16_t>(mask) << 8U)) != 0U ? 8U : 0U));
}

[[maybe_unused]] std::uint8_t tile_pixel_2bpp(
    const simulation::SnesPpuState& ppu,
    std::uint16_t character_base,
    std::uint16_t tile,
    std::uint32_t x,
    std::uint32_t y) noexcept {
    if ((tile & 0x4000U) != 0U) x = 7U - x;
    if ((tile & 0x8000U) != 0U) y = 7U - y;
    const auto tile_number = static_cast<std::uint32_t>(tile & 0x03ffU);
    const auto base = (static_cast<std::uint32_t>(character_base) * 2U
        + tile_number * 16U + y * 2U) & 0xffffU;
    const auto planes = static_cast<std::uint16_t>(ppu.vram[base])
        | (static_cast<std::uint16_t>(ppu.vram[(base + 1U) & 0xffffU]) << 8U);
    const auto mask = static_cast<std::uint8_t>(0x80U >> x);
    return static_cast<std::uint8_t>(
        ((planes & mask) != 0U ? 1U : 0U)
        | ((planes & (static_cast<std::uint16_t>(mask) << 8U)) != 0U ? 2U : 0U));
}

[[maybe_unused]] std::uint8_t tile_pixel_8bpp(
    const simulation::SnesPpuState& ppu,
    std::uint16_t character_base,
    std::uint16_t tile,
    std::uint32_t x,
    std::uint32_t y) noexcept {
    if ((tile & 0x4000U) != 0U) x = 7U - x;
    if ((tile & 0x8000U) != 0U) y = 7U - y;
    const auto tile_number = static_cast<std::uint32_t>(tile & 0x03ffU);
    const auto base = (static_cast<std::uint32_t>(character_base) * 2U
        + tile_number * 64U + y * 2U) & 0xffffU;
    const auto mask = static_cast<std::uint8_t>(0x80U >> x);
    std::uint8_t colour{};
    for (std::uint32_t pair = 0; pair < 4U; ++pair) {
        const auto pair_base = (base + pair * 16U) & 0xffffU;
        if ((ppu.vram[pair_base] & mask) != 0U) {
            colour = static_cast<std::uint8_t>(colour | (1U << (pair * 2U)));
        }
        if ((ppu.vram[(pair_base + 1U) & 0xffffU] & mask) != 0U) {
            colour = static_cast<std::uint8_t>(colour | (2U << (pair * 2U)));
        }
    }
    return colour;
}


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

bool selected_priority(std::uint16_t tile, TilePriorityPass pass) noexcept {
    if (pass == TilePriorityPass::all) return true;
    const auto high = (tile & 0x2000U) != 0U;
    return high == (pass == TilePriorityPass::high);
}

std::int32_t mosaic_coordinate(
    std::int32_t coordinate,
    std::uint8_t mosaic,
    std::uint8_t layer_mask) noexcept {
    if ((mosaic & layer_mask) == 0U) return coordinate;
    const auto size = static_cast<std::int32_t>((mosaic >> 4U) + 1U);
    auto remainder = coordinate % size;
    if (remainder < 0) remainder += size;
    return coordinate - remainder;
}

} // namespace

void BackgroundRenderer::draw_bg1(
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

void BackgroundRenderer::draw_bg2(
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

void BackgroundRenderer::draw_bg3(
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

} // namespace starfox::render
