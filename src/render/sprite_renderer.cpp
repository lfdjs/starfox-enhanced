#include "starfox/app/perf_profiler.hpp"
#include "starfox/render/sprite_renderer.hpp"

#include "starfox/simulation/game_simulation.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <unordered_set>

namespace starfox::render {
namespace {

constexpr std::array<std::array<std::uint8_t, 2>, 6> kObjectSizes{{
    {{8, 16}}, {{8, 32}}, {{8, 64}}, {{16, 32}}, {{16, 64}}, {{32, 64}},
}};

using ObjectTileRow =
    std::array<std::uint8_t, 8>;

ObjectTileRow object_tile_row(
    const simulation::SnesPpuState& ppu,
    std::uint16_t tile_number,
    std::uint32_t tile_column,
    std::uint32_t source_y) noexcept {

    const auto table_base =
        static_cast<std::uint32_t>(
            ppu.object_select & 7U)
        * 0x2000U;

    const auto name_gap =
        static_cast<std::uint32_t>(
            ((ppu.object_select >> 3U)
                & 3U)
            + 1U)
        * 0x1000U;

    auto tile_base =
        table_base;

    if ((tile_number & 0x100U)
        != 0U) {

        tile_base +=
            name_gap;
    }

    const auto tile =
        static_cast<std::uint32_t>(
            tile_number & 0xffU)
        + (source_y >> 3U) * 16U
        + tile_column;

    const auto address =
        (tile_base * 2U
            + tile * 32U
            + (source_y & 7U)
                * 2U)
        & 0xffffU;

    const auto plane01 =
        static_cast<std::uint16_t>(
            ppu.vram[address])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (address + 1U)
                    & 0xffffU])
            << 8U);

    const auto plane23 =
        static_cast<std::uint16_t>(
            ppu.vram[
                (address + 16U)
                    & 0xffffU])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (address + 17U)
                    & 0xffffU])
            << 8U);

    ObjectTileRow result{};

    for (std::uint32_t x = 0U;
         x < result.size();
         ++x) {

        const auto mask =
            static_cast<std::uint8_t>(
                0x80U >> x);

        result[x] =
            static_cast<std::uint8_t>(
                ((plane01 & mask) != 0U
                    ? 1U : 0U)

                | ((plane01
                        & (static_cast<
                            std::uint16_t>(
                                mask)
                            << 8U))
                    != 0U
                    ? 2U : 0U)

                | ((plane23 & mask) != 0U
                    ? 4U : 0U)

                | ((plane23
                        & (static_cast<
                            std::uint16_t>(
                                mask)
                            << 8U))
                    != 0U
                    ? 8U : 0U));
    }

    return result;
}


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

} // namespace

void SpriteRenderer::draw_objects(
    const simulation::SnesPpuState& ppu,
    Framebuffer& target,
    std::optional<std::uint8_t> priority,
    std::int32_t horizontal_origin,
    bool extend_horizontal,
    bool anchor_edge_hud,
    const HudLayout* hud_layout,
    bool suppress_configurable_hud,
    bool suppress_original_shield_label) const noexcept {
    starfox::app::perf::ScopedTimer
        perf_timer_objects{
            starfox::app::perf::Bucket::objects};

    if ((ppu.main_screen & 0x10U) == 0U) return;
    const auto size_selection = static_cast<std::size_t>(
        (ppu.object_select >> 5U) & 7U);
    const auto sizes = kObjectSizes[size_selection < kObjectSizes.size()
        ? size_selection : kObjectSizes.size() - 1U];

    const auto target_width =
        static_cast<std::int32_t>(
            target.width());

    const auto target_height =
        static_cast<std::int32_t>(
            target.height());

    // getenv() is comparatively expensive on a console runtime. HUD OAM
    // discovery is a developer-only feature, so evaluate it once per pass
    // instead of once for every one of the 128 OAM records.
    const bool log_hud_oam =
        std::getenv(
            "STARFOX_LOG_HUD_OAM")
        != nullptr;

    // Lower OAM indices win sprite-to-sprite priority, so paint in reverse.
    for (std::size_t object = 128U; object-- > 0U;) {
        const auto low = object * 4U;
        const auto high = 512U + object / 4U;
        const auto high_bits = static_cast<std::uint8_t>(
            ppu.oam[high] >> ((object & 3U) * 2U));
        // SPRITES.ASM clears unused low-OAM records with STZ but does not
        // always rewrite their packed high-table size bit. Treat the zeroed
        // four-byte record as empty regardless of that stale bit. Otherwise
        // a large tile-zero route dot wraps into a blinking strip at (0, 0).
        if (ppu.oam[low] == 0U
            && ppu.oam[low + 1U] == 0U
            && ppu.oam[low + 2U] == 0U
            && ppu.oam[low + 3U] == 0U) continue;
        auto x = static_cast<std::int32_t>(ppu.oam[low])
            | (static_cast<std::int32_t>(high_bits & 1U) << 8U);
        if (x >= 256) x -= 512;
        const auto y_byte = ppu.oam[low + 1U];
        auto object_origin = horizontal_origin;
        if (anchor_edge_hud && horizontal_origin > 0
            && (y_byte < 32U || y_byte >= 168U)) {
            // Only the top/bottom gameplay OAM bands are edge HUD artwork.
            // Keep those labels, lives and bombs at the expanded edges. The
            // middle band contains the cockpit crosshair and communication
            // portraits, which must remain centred as a single composition.
            object_origin = x < 128 ? 0 : horizontal_origin * 2;
        }
        const auto tile = static_cast<std::uint16_t>(ppu.oam[low + 2U])
            | (static_cast<std::uint16_t>(ppu.oam[low + 3U] & 1U) << 8U);
        // EX deliberately relocates the life icon/count beside the lower-left
        // shield readout. Position-only classification therefore tied both
        // groups to the Shield layout. These are the source HUD life tiles in
        // retail and EX (EX substitutes tile 230 for the final digit glyph),
        // so identify the independent group before applying band heuristics.
        const auto lives_tile = tile == 189U || tile == 226U
            || tile == 229U || tile == 230U;
        auto element = std::optional<HudElement>{};
        if (lives_tile || (y_byte < 32U && x < 128)) {
            element = HudElement::lives;
        } else if (y_byte >= 168U) {
            element = x < 128
                ? HudElement::shield : HudElement::bombs_boost;
        } else if (y_byte >= 128U && x < 128) {
            element = HudElement::comms;
        }
        // Retail SHIELD is encoded as four 8x8 OAM tiles at $CB-$CE.
        // PT-BR replaces only those source text tiles. Keep the shield meter,
        // life counter, bomb icons and every other HUD sprite untouched.
        if (suppress_original_shield_label
            && element
            && *element == HudElement::shield
            && tile >= 0xCBU
            && tile <= 0xCEU) {
            continue;
        }

        if (suppress_configurable_hud && element) continue;
        const auto object_offset = hud_layout != nullptr && element
            ? (*hud_layout)[*element] : HudOffset{};
        const auto size = static_cast<std::uint32_t>(
            sizes[(high_bits >> 1U) & 1U]);
        const auto palette = static_cast<std::uint8_t>(
            (ppu.oam[low + 3U] >> 1U) & 7U);
        const auto object_priority = static_cast<std::uint8_t>(
            (ppu.oam[low + 3U] >> 4U) & 3U);
        if (priority && object_priority != *priority) continue;

        if (log_hud_oam
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
                    << '\n';
            }
        }

        const auto flip_x = (ppu.oam[low + 3U] & 0x40U) != 0U;
        const auto flip_y = (ppu.oam[low + 3U] & 0x80U) != 0U;

        const auto palette_base =
            static_cast<std::uint8_t>(
                128U
                + palette * 16U);

        const auto tile_columns =
            (size + 7U) >> 3U;

        // The largest SNES object supported by this renderer is 64 pixels
        // wide, therefore at most eight 8x8 tile columns exist in a row.
        std::array<ObjectTileRow, 8>
            decoded_rows{};

        for (std::uint32_t destination_y = 0;
             destination_y < size;
             ++destination_y) {

            const auto source_y =
                flip_y
                    ? size - 1U
                        - destination_y
                    : destination_y;

            // Decode every 8-pixel source tile row once. The previous path
            // decoded the same four SNES bitplanes again for every pixel.
            for (std::uint32_t tile_column = 0U;
                 tile_column < tile_columns;
                 ++tile_column) {

                decoded_rows[tile_column] =
                    object_tile_row(
                        ppu,
                        tile,
                        tile_column,
                        source_y);
            }

            const auto raw_y =
                static_cast<std::int32_t>(
                    y_byte)
                + object_offset.y
                + static_cast<std::int32_t>(
                    destination_y);

            const std::array<
                std::int32_t,
                2>
                screen_ys{
                    raw_y,
                    raw_y - 256};

            for (const auto screen_y :
                 screen_ys) {

                if (screen_y < 0
                    || screen_y
                        >= target_height) {

                    continue;
                }

                auto* const target_row =
                    target.row_data(
                        static_cast<
                            std::uint32_t>(
                                screen_y));

                for (std::uint32_t destination_x = 0;
                     destination_x < size;
                     ++destination_x) {

                    const auto screen_x =
                        x
                        + object_origin
                        + object_offset.x
                        + static_cast<
                            std::int32_t>(
                                destination_x);

                    if (!extend_horizontal
                        && (screen_x
                                < horizontal_origin
                            || screen_x
                                >= horizontal_origin
                                    + 256)) {

                        continue;
                    }

                    if (screen_x < 0
                        || screen_x
                            >= target_width) {

                        continue;
                    }

                    const auto source_x =
                        flip_x
                            ? size - 1U
                                - destination_x
                            : destination_x;

                    const auto tile_column =
                        source_x >> 3U;

                    const auto tile_pixel_x =
                        source_x & 7U;

                    const auto pixel =
                        decoded_rows[
                            tile_column][
                                tile_pixel_x];

                    if (pixel == 0U) {
                        continue;
                    }

                    target_row[
                        static_cast<
                            std::uint32_t>(
                                screen_x)] =
                        static_cast<
                            std::uint8_t>(
                                palette_base
                                + pixel);
                }
            }
        }
    }
}

void SpriteRenderer::draw_meters(
    const simulation::MeterState& meters,
    Framebuffer& target,
    bool anchor_to_edges,
    const HudLayout* hud_layout) const noexcept {
    starfox::app::perf::ScopedTimer
        perf_timer_objects{
            starfox::app::perf::Bucket::objects};

    if (!meters.enabled) return;
    const auto solid = [&target](
        std::int32_t x,
        std::int32_t y,
        std::int32_t width,
        std::int32_t height,
        std::uint8_t colour) {

        if (width <= 0
            || height <= 0) {

            return;
        }

        const auto target_width =
            static_cast<std::int32_t>(
                target.width());

        const auto target_height =
            static_cast<std::int32_t>(
                target.height());

        const auto first_x =
            std::max<std::int32_t>(
                0,
                x);

        const auto final_x =
            std::min<std::int32_t>(
                target_width,
                x + width);

        if (first_x >= final_x) {
            return;
        }

        const auto indexed_colour =
            static_cast<std::uint8_t>(
                7U * 16U
                + colour);

        for (std::int32_t row = 0;
             row < height;
             ++row) {

            const auto destination_y =
                y + row;

            if (destination_y < 0
                || destination_y
                    >= target_height) {

                continue;
            }

            auto* const destination =
                target.row_data(
                    static_cast<
                        std::uint32_t>(
                            destination_y));

            std::fill(
                destination + first_x,
                destination + final_x,
                indexed_colour);
        }
    };
    const auto box = [&solid](std::int32_t x, std::int32_t y,
                              std::int32_t width, std::int32_t height,
                              std::uint8_t colour) {
        if (width <= 0 || height <= 0) return;
        solid(x, y, width, 1, colour);
        solid(x, y + height - 1, width, 1, colour);
        if (height > 2) {
            solid(x, y + 1, 1, height - 2, colour);
            solid(x + width - 1, y + 1, 1, height - 2, colour);
        }
    };
    const auto left_x = anchor_to_edges ? 24 : 8;
    const auto right_x = anchor_to_edges
        ? static_cast<std::int32_t>(target.width()) - 64 : 176;
    const auto shield = hud_layout == nullptr
        ? HudOffset{} : (*hud_layout)[HudElement::shield];
    const auto boost = hud_layout == nullptr
        ? HudOffset{} : (*hud_layout)[HudElement::bombs_boost];
    const auto boss = hud_layout == nullptr
        ? HudOffset{} : (*hud_layout)[HudElement::boss_health];
    if (meters.extended) {
        const auto source_left_x = [anchor_to_edges](std::int32_t x) {
            return x + (anchor_to_edges ? 16 : 0);
        };
        const auto source_right_x = [anchor_to_edges, &target](std::int32_t x) {
            return anchor_to_edges
                ? x + static_cast<std::int32_t>(target.width()) - 240
                : x;
        };
        if (meters.boost_enabled) {
            const auto x = (meters.player_two_activated
                ? source_left_x(0) : source_right_x(176)) + boost.x;
            box(x, 176 + boost.y, 40, 8, 13U);
            solid(x + 2, 178 + boost.y,
                std::min<std::uint8_t>(meters.boost, 36U), 4, 6U);
        }
        if (!meters.second_player_view) {
            if (!meters.player_one_dead) {
                const auto x = source_left_x(1) + shield.x;
                // Leave two source pixels between the lower-left SHIELD
                // label and its host-rendered meter. Top-row multiplayer
                // meters retain their cartridge coordinates.
                const auto y = (meters.player_two_activated ? 7 : 182)
                    + shield.y;
                box(x, y, meters.player_health_width, 8, 13U);
                solid(x + 2, y + 2,
                    std::min(meters.damage, meters.player_health_max), 4,
                    meters.shield_up ? 7U : 2U);
            }
            if (meters.damage_two != 0U) {
                const auto x = source_right_x(115) + boost.x;
                const auto y = 7 + boost.y;
                box(x, y, meters.player_health_width, 8, 13U);
                solid(x + 2, y + 2,
                    std::min(meters.damage_two, meters.player_health_max), 4,
                    meters.shield_up_two ? 7U : 2U);
            } else if (meters.player_two_activated) {
                const auto x = source_right_x(115) + boost.x;
                const auto y = 7 + boost.y;
                box(x, y, meters.player_health_width, 8, 11U);
                solid(x + 2, y + 2, meters.player_health_max, 4, 0U);
            }
        }
    } else {
        box(left_x + shield.x, 178 + shield.y, 40, 8, 13U);
        solid(left_x + shield.x + 2, 180 + shield.y,
            std::min<std::uint8_t>(meters.damage, 36U), 4,
            meters.shield_up ? 7U : 2U);
        box(right_x + boost.x, 176 + boost.y, 40, 8, 13U);
        solid(right_x + boost.x + 2, 178 + boost.y,
            std::min<std::uint8_t>(meters.boost, 36U), 4, 6U);
    }

    auto maximum = meters.boss_max_health;
    auto current = meters.boss_health;
    if (static_cast<unsigned>(current) >= static_cast<unsigned>(maximum) + 10U) {
        current = 0U;
    }
    if (maximum == 0U) return;
    const auto half_scale = (maximum & 0x80U) != 0U;
    auto meter_width = half_scale ? maximum >> 1U : maximum;
    meter_width = static_cast<std::uint8_t>(meter_width + 4U);
    const auto boss_x = (anchor_to_edges
        ? static_cast<std::int32_t>(target.width()) - 18
            - static_cast<std::int32_t>(meter_width)
        : 222 - static_cast<std::int32_t>(meter_width)) + boss.x;
    const auto boss_y = (meters.extended && meters.player_two_activated
        ? 178 : 2) + boss.y;
    box(boss_x, boss_y, meter_width, 6, 14U);
    if (half_scale) current >>= 1U;
    solid(boss_x + 2, boss_y + 2, current, 2, 2U);
}

} // namespace starfox::render
