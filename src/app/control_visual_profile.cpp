#include "starfox/app/control_visual_profile.hpp"

#include "starfox/render/framebuffer.hpp"
#include "starfox/render/scaled_text_renderer.hpp"

#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <string>

#if defined(STARFOX_SWITCH_RUNTIME)
#include <switch.h>
#endif

namespace starfox::app {
namespace {

constexpr ControlHintBindings keyboard_bindings{
    "ARROWS", "Z FIRE", "X BOMB", "A BOOST", "S BRAKE", "ENTER", "' SELECT"};
constexpr ControlHintBindings generic_bindings{
    "STICK/DPAD", "SOUTH FIRE", "EAST BOMB", "WEST BOOST", "NORTH BRAKE", "START", "BACK"};
constexpr ControlHintBindings xbox_bindings{
    "LS/DPAD", "A FIRE", "B BOMB", "X BOOST", "Y BRAKE", "MENU", "VIEW"};
constexpr ControlHintBindings playstation_bindings{
    "LS/DPAD", "CROSS FIRE", "CIRCLE BOMB", "SQUARE BOOST", "TRIANGLE BRAKE", "OPTIONS", "SHARE"};
constexpr ControlHintBindings switch_bindings{
    "LS/DPAD", "B FIRE", "A BOMB", "Y BOOST", "X BRAKE", "+ START", "- SELECT"};

constexpr std::array<ControlHintAnchor, 7> compact_anchors{{
    {ControlHintAction::movement, 0, 57},
    {ControlHintAction::fire, 58, 57},
    {ControlHintAction::bomb, 58, 66},
    {ControlHintAction::boost, 0, 66},
    {ControlHintAction::brake, 0, 75},
    {ControlHintAction::start, 58, 75},
    {ControlHintAction::select, 58, 84},
}};

constexpr ControlHintLayout make_layout(ControlVisualSprite sprite) {
    return {sprite, 12, 13, 88, 38, compact_anchors};
}

constexpr std::array layouts{
    make_layout(ControlVisualSprite::keyboard),
    make_layout(ControlVisualSprite::generic_gamepad),
    make_layout(ControlVisualSprite::dualshock4),
    make_layout(ControlVisualSprite::dualsense),
    make_layout(ControlVisualSprite::xbox),
    make_layout(ControlVisualSprite::switch_pro_controller),
    make_layout(ControlVisualSprite::switch_dual_joycon),
    make_layout(ControlVisualSprite::switch_handheld),
};

std::size_t profile_index(ControlVisualProfile profile) noexcept {
    return std::min<std::size_t>(static_cast<std::size_t>(profile),
        layouts.size() - 1U);
}

void fill_rect(render::Framebuffer& target, std::int32_t x, std::int32_t y,
    std::int32_t width, std::int32_t height, std::uint8_t colour) noexcept {
    for (auto row = 0; row < height; ++row) {
        for (auto column = 0; column < width; ++column) {
            target.set(x + column, y + row, colour);
        }
    }
}

void outline_rect(render::Framebuffer& target, std::int32_t x, std::int32_t y,
    std::int32_t width, std::int32_t height, std::uint8_t colour) noexcept {
    fill_rect(target, x, y, width, 1, colour);
    fill_rect(target, x, y + height - 1, width, 1, colour);
    fill_rect(target, x, y, 1, height, colour);
    fill_rect(target, x + width - 1, y, 1, height, colour);
}

void draw_dpad(render::Framebuffer& target, std::int32_t x, std::int32_t y,
    std::uint8_t colour) noexcept {
    fill_rect(target, x + 4, y, 5, 13, colour);
    fill_rect(target, x, y + 4, 13, 5, colour);
}

void draw_button(render::Framebuffer& target, std::int32_t x, std::int32_t y,
    std::uint8_t colour) noexcept {
    fill_rect(target, x + 1, y, 3, 5, colour);
    fill_rect(target, x, y + 1, 5, 3, colour);
}

void draw_gamepad(render::Framebuffer& target, const ControlHintLayout& layout,
    std::int32_t origin_x, std::int32_t origin_y, std::uint8_t body,
    std::uint8_t outline, std::uint8_t accent, bool separated) noexcept {
    const auto x = origin_x + layout.sprite_x;
    const auto y = origin_y + layout.sprite_y;
    const auto w = layout.sprite_width;
    const auto h = layout.sprite_height;
    if (separated) {
        fill_rect(target, x + 4, y + 2, 23, h - 4, body);
        fill_rect(target, x + w - 27, y + 2, 23, h - 4, body);
        outline_rect(target, x + 4, y + 2, 23, h - 4, outline);
        outline_rect(target, x + w - 27, y + 2, 23, h - 4, outline);
    } else {
        fill_rect(target, x + 7, y + 2, w - 14, h - 8, body);
        fill_rect(target, x + 2, y + 10, 16, h - 4, body);
        fill_rect(target, x + w - 18, y + 10, 16, h - 4, body);
        outline_rect(target, x + 7, y + 2, w - 14, h - 8, outline);
    }
    draw_dpad(target, x + 17, y + 12, outline);
    draw_button(target, x + w - 25, y + 10, accent);
    draw_button(target, x + w - 17, y + 17, accent);
    draw_button(target, x + w - 33, y + 17, accent);
    draw_button(target, x + w - 25, y + 24, accent);
    fill_rect(target, x + w / 2 - 8, y + 17, 5, 2, outline);
    fill_rect(target, x + w / 2 + 3, y + 17, 5, 2, outline);
    switch (layout.sprite) {
    case ControlVisualSprite::xbox:
        draw_button(target, x + 33, y + 9, accent);
        draw_button(target, x + 48, y + 24, outline);
        break;
    case ControlVisualSprite::dualshock4:
        outline_rect(target, x + w / 2 - 11, y + 7, 22, 8, outline);
        draw_button(target, x + 34, y + 25, outline);
        draw_button(target, x + w - 39, y + 25, outline);
        break;
    case ControlVisualSprite::dualsense:
        outline_rect(target, x + w / 2 - 12, y + 6, 24, 10, outline);
        fill_rect(target, x + w / 2 - 5, y + 9, 10, 1, accent);
        draw_button(target, x + 34, y + 26, outline);
        draw_button(target, x + w - 39, y + 26, outline);
        break;
    case ControlVisualSprite::switch_pro_controller:
        draw_button(target, x + 34, y + 24, outline);
        draw_button(target, x + w - 39, y + 24, outline);
        outline_rect(target, x + w / 2 - 3, y + 8, 6, 6, accent);
        break;
    default: break;
    }
}

void draw_keyboard(render::Framebuffer& target, const ControlHintLayout& layout,
    std::int32_t origin_x, std::int32_t origin_y, std::uint8_t body,
    std::uint8_t outline, std::uint8_t accent) noexcept {
    const auto x = origin_x + layout.sprite_x;
    const auto y = origin_y + layout.sprite_y;
    fill_rect(target, x, y + 3, layout.sprite_width, layout.sprite_height - 6, body);
    outline_rect(target, x, y + 3, layout.sprite_width,
        layout.sprite_height - 6, outline);
    for (auto row = 0; row < 3; ++row) {
        for (auto column = 0; column < 10; ++column) {
            fill_rect(target, x + 5 + column * 8, y + 8 + row * 8,
                5, 5, (row == 2 && column >= 7) ? accent : outline);
        }
    }
}

void draw_handheld(render::Framebuffer& target, const ControlHintLayout& layout,
    std::int32_t origin_x, std::int32_t origin_y, std::uint8_t body,
    std::uint8_t outline, std::uint8_t accent) noexcept {
    const auto x = origin_x + layout.sprite_x;
    const auto y = origin_y + layout.sprite_y;
    fill_rect(target, x, y + 2, layout.sprite_width, layout.sprite_height - 4, body);
    outline_rect(target, x, y + 2, layout.sprite_width,
        layout.sprite_height - 4, outline);
    fill_rect(target, x + 18, y + 6, layout.sprite_width - 36,
        layout.sprite_height - 12, 0U);
    draw_dpad(target, x + 4, y + 13, outline);
    draw_button(target, x + layout.sprite_width - 12, y + 11, accent);
    draw_button(target, x + layout.sprite_width - 8, y + 18, accent);
}

std::string_view label_for(const ControlHintBindings& labels,
    ControlHintAction action) noexcept {
    switch (action) {
    case ControlHintAction::movement: return labels.movement;
    case ControlHintAction::fire: return labels.fire;
    case ControlHintAction::bomb: return labels.bomb;
    case ControlHintAction::boost: return labels.boost;
    case ControlHintAction::brake: return labels.brake;
    case ControlHintAction::start: return labels.start;
    case ControlHintAction::select: return labels.select;
    }
    return {};
}

} // namespace

ControlVisualProfile detect_control_visual_profile(
    const ControlDetectionInput& input) noexcept {
    if (input.platform == ControlPlatform::switch_console) {
        if (input.handheld) return ControlVisualProfile::switch_handheld;
        if (input.device == ControlDeviceKind::switch_dual_joycon) {
            return ControlVisualProfile::switch_dual_joycon;
        }
        return ControlVisualProfile::switch_pro_controller;
    }
    switch (input.device) {
    case ControlDeviceKind::none: return ControlVisualProfile::keyboard_pc;
    case ControlDeviceKind::xbox: return ControlVisualProfile::xbox;
    case ControlDeviceKind::dualshock4: return ControlVisualProfile::dualshock4;
    case ControlDeviceKind::dualsense: return ControlVisualProfile::dualsense;
    case ControlDeviceKind::switch_pro_controller:
        return ControlVisualProfile::switch_pro_controller;
    case ControlDeviceKind::switch_dual_joycon:
        return ControlVisualProfile::switch_dual_joycon;
    case ControlDeviceKind::generic_gamepad:
    default: return ControlVisualProfile::generic_gamepad_pc;
    }
}

ControlVisualProfile detect_control_visual_profile(SDL_Gamepad* gamepad) noexcept {
#if defined(STARFOX_SWITCH_RUNTIME)
    ControlDetectionInput input{ControlPlatform::switch_console,
        ControlDeviceKind::switch_pro_controller, false};
    input.handheld = appletGetOperationMode() == AppletOperationMode_Handheld;
    if (!input.handheld
        && (hidGetNpadStyleSet(HidNpadIdType_No1)
            & HidNpadStyleTag_NpadJoyDual) != 0U) {
        input.device = ControlDeviceKind::switch_dual_joycon;
    }
    return detect_control_visual_profile(input);
#else
    if (gamepad == nullptr) {
        return detect_control_visual_profile({});
    }
    auto kind = ControlDeviceKind::generic_gamepad;
    switch (SDL_GetGamepadType(gamepad)) {
    case SDL_GAMEPAD_TYPE_XBOX360:
    case SDL_GAMEPAD_TYPE_XBOXONE: kind = ControlDeviceKind::xbox; break;
    case SDL_GAMEPAD_TYPE_PS4: kind = ControlDeviceKind::dualshock4; break;
    case SDL_GAMEPAD_TYPE_PS5: kind = ControlDeviceKind::dualsense; break;
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO:
        kind = ControlDeviceKind::switch_pro_controller; break;
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR:
        kind = ControlDeviceKind::switch_dual_joycon; break;
    default: break;
    }
    return detect_control_visual_profile({ControlPlatform::pc, kind, false});
#endif
}

const ControlHintBindings& control_hint_bindings(
    ControlVisualProfile profile) noexcept {
    switch (profile) {
    case ControlVisualProfile::keyboard_pc: return keyboard_bindings;
    case ControlVisualProfile::xbox: return xbox_bindings;
    case ControlVisualProfile::dualshock4:
    case ControlVisualProfile::dualsense: return playstation_bindings;
    case ControlVisualProfile::switch_pro_controller:
    case ControlVisualProfile::switch_dual_joycon:
    case ControlVisualProfile::switch_handheld: return switch_bindings;
    case ControlVisualProfile::generic_gamepad_pc:
    default: return generic_bindings;
    }
}

const ControlHintLayout& control_hint_layout(ControlVisualProfile profile) noexcept {
    return layouts[profile_index(profile)];
}

std::string_view control_visual_profile_name(ControlVisualProfile profile) noexcept {
    constexpr std::array names{"KEYBOARD", "GAMEPAD", "DUALSHOCK 4", "DUALSENSE",
        "XBOX", "SWITCH PRO", "DUAL JOY-CON", "HANDHELD"};
    return names[profile_index(profile)];
}

void draw_control_visual_profile(ControlVisualProfile profile,
    render::Framebuffer& framebuffer,
    const render::ScaledTextRenderer& text_renderer,
    std::int32_t viewport_origin) noexcept {
    constexpr std::uint8_t panel = 1U;
    constexpr std::uint8_t body = 4U;
    constexpr std::uint8_t outline = 14U;
    constexpr std::uint8_t accent = 7U;
    constexpr auto panel_x = 140;
    constexpr auto panel_y = 20;
    constexpr auto panel_width = 116;
    constexpr auto panel_height = 96;
    const auto x = panel_x + viewport_origin;
    const auto& layout = control_hint_layout(profile);
    fill_rect(framebuffer, x, panel_y, panel_width, panel_height, panel);
    outline_rect(framebuffer, x, panel_y, panel_width, panel_height, outline);
    const auto title = control_visual_profile_name(profile);
    text_renderer.draw_utf8(title,
        x + panel_width / 2 - text_renderer.measure_utf8(title) / 2,
        panel_y + 3, framebuffer, outline);

    switch (layout.sprite) {
    case ControlVisualSprite::keyboard:
        draw_keyboard(framebuffer, layout, x, panel_y, body, outline, accent);
        break;
    case ControlVisualSprite::switch_dual_joycon:
        draw_gamepad(framebuffer, layout, x, panel_y, body, outline, accent, true);
        break;
    case ControlVisualSprite::switch_handheld:
        draw_handheld(framebuffer, layout, x, panel_y, body, outline, accent);
        break;
    default:
        draw_gamepad(framebuffer, layout, x, panel_y, body, outline, accent, false);
        break;
    }

    const auto& labels = control_hint_bindings(profile);
    for (const auto& anchor : layout.anchors) {
        text_renderer.draw_utf8(label_for(labels, anchor.action),
            x + anchor.x, panel_y + anchor.y, framebuffer, outline);
    }
}

} // namespace starfox::app
