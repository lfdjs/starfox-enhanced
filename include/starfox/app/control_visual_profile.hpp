#pragma once

#include <array>
#include <cstdint>
#include <string_view>

struct SDL_Gamepad;

namespace starfox::render {
class Framebuffer;
class ScaledTextRenderer;
}

namespace starfox::app {

enum class ControlVisualProfile : std::uint8_t {
    keyboard_pc,
    generic_gamepad_pc,
    dualshock4,
    dualsense,
    xbox,
    switch_pro_controller,
    switch_single_joycon,
    switch_dual_joycon,
    switch_handheld,
};

enum class ControlPlatform : std::uint8_t {
    pc,
    switch_console,
};

enum class ControlDeviceKind : std::uint8_t {
    none,
    generic_gamepad,
    xbox,
    dualshock4,
    dualsense,
    switch_pro_controller,
    switch_single_joycon,
    switch_dual_joycon,
};

struct ControlDetectionInput {
    ControlPlatform platform{ControlPlatform::pc};
    ControlDeviceKind device{ControlDeviceKind::none};
    bool handheld{};
};

struct ControlHintBindings {
    std::string_view movement;
    std::string_view fire;
    std::string_view bomb;
    std::string_view boost;
    std::string_view brake;
    std::string_view start;
    std::string_view select;
};

enum class ControlHintAction : std::uint8_t {
    movement,
    fire,
    bomb,
    boost,
    brake,
    start,
    select,
};

enum class ControlVisualSprite : std::uint8_t {
    keyboard,
    generic_gamepad,
    xbox,
    dualshock4,
    dualsense,
    switch_pro_controller,
    switch_single_joycon,
    switch_dual_joycon,
    switch_handheld,
};

struct ControlHintAnchor {
    ControlHintAction action{};
    std::int16_t x{};
    std::int16_t y{};
};

struct ControlHintLayout {
    ControlVisualSprite sprite{ControlVisualSprite::generic_gamepad};
    std::int16_t sprite_x{};
    std::int16_t sprite_y{};
    std::int16_t sprite_width{};
    std::int16_t sprite_height{};
    std::array<ControlHintAnchor, 7> anchors{};
};

[[nodiscard]] ControlVisualProfile detect_control_visual_profile(
    const ControlDetectionInput& input) noexcept;
[[nodiscard]] ControlVisualProfile detect_control_visual_profile(
    SDL_Gamepad* gamepad) noexcept;
[[nodiscard]] const ControlHintBindings& control_hint_bindings(
    ControlVisualProfile profile) noexcept;
[[nodiscard]] const ControlHintLayout& control_hint_layout(
    ControlVisualProfile profile) noexcept;
[[nodiscard]] std::string_view control_visual_profile_name(
    ControlVisualProfile profile) noexcept;
[[nodiscard]] std::int32_t measure_control_mini_text(
    std::string_view text) noexcept;
void draw_control_mini_text(
    render::Framebuffer& framebuffer,
    std::string_view text,
    std::int32_t x,
    std::int32_t y,
    std::uint8_t colour) noexcept;

void draw_control_visual_profile(
    ControlVisualProfile profile,
    render::Framebuffer& framebuffer,
    const render::ScaledTextRenderer& text_renderer,
    std::int32_t viewport_origin,
    const std::array<std::uint16_t, 256>& cgram) noexcept;

} // namespace starfox::app
