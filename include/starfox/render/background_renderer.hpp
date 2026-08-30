#pragma once

#include "starfox/render/framebuffer.hpp"
#include "starfox/simulation/snes_ppu.hpp"

#include <cstdint>
#include <vector>

namespace starfox::render {

enum class TilePriorityPass {
    all,
    low,
    high,
};

class BackgroundRenderer {
public:
    void draw_bg1(
        const simulation::SnesPpuState& ppu,
        Framebuffer& target,
        TilePriorityPass priority = TilePriorityPass::all,
        std::int32_t horizontal_origin = 0,
        bool extend_horizontal = true,
        std::uint32_t horizontal_inset = 0) const noexcept;
    void draw_bg2(
        const simulation::SnesPpuState& ppu,
        std::int32_t scroll_x,
        std::int32_t scroll_y,
        Framebuffer& target,
        TilePriorityPass priority = TilePriorityPass::all,
        std::int32_t horizontal_origin = 0,
        bool extend_horizontal = true) const noexcept;
    void draw_bg3(
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

} // namespace starfox::render
