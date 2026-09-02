#include "starfox/app/control_visual_profile.hpp"

#include "starfox/render/framebuffer.hpp"
#include "starfox/render/palette.hpp"
#include "starfox/render/scaled_text_renderer.hpp"

#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <limits>
#include <string>

#if defined(STARFOX_SWITCH_RUNTIME)
#include <switch.h>
#endif

namespace starfox::app {
namespace {

#include "dualsense_pixel_art.inc"

constexpr ControlHintBindings keyboard_bindings{
    "ARROWS", "Z FIRE", "X BOMB", "A BOOST", "S BRAKE", "ENTER", "' SELECT"};
constexpr ControlHintBindings generic_bindings{
    "STICK/DPAD", "SOUTH FIRE", "EAST BOMB", "WEST BOOST", "NORTH BRAKE", "START", "BACK"};
constexpr ControlHintBindings xbox_bindings{
    "LS/DPAD", "X FIRE", "B BOMB", "Y BOOST", "A BRAKE", "MENU PAUSE", "VIEW"};
constexpr ControlHintBindings playstation_bindings{
    "MOVE", "[] FIRE", "O BOMB", "^ BOOST", "X BRAKE", "OPTIONS PAUSE", "SHARE"};
constexpr ControlHintBindings switch_bindings{
    "LS/DPAD", "Y FIRE", "A BOMB", "X BOOST", "B BRAKE", "+ PAUSE", "- VIEW"};
constexpr ControlHintBindings switch_single_joycon_bindings{
    "STICK", "LEFT FIRE", "RIGHT BOMB", "TOP BOOST", "BOTTOM BRAKE",
    "+/- PAUSE", "STICK PRESS VIEW"};

constexpr std::array<ControlHintAnchor, 7> compact_anchors{{
    {ControlHintAction::movement, 0, 58},
    {ControlHintAction::fire, 58, 49},
    {ControlHintAction::bomb, 58, 58},
    {ControlHintAction::boost, 0, 67},
    {ControlHintAction::brake, 58, 67},
    {ControlHintAction::start, 0, 76},
    {ControlHintAction::select, 58, 76},
}};

constexpr std::array<ControlHintAnchor, 7> dualsense_anchors{{
    {ControlHintAction::movement, 0, 80},
    {ControlHintAction::fire, 76, 16},
    {ControlHintAction::bomb, 76, 27},
    {ControlHintAction::boost, 76, 38},
    {ControlHintAction::brake, 76, 49},
    {ControlHintAction::start, 0, 76},
    {ControlHintAction::select, 58, 76},
}};

constexpr ControlHintLayout make_layout(ControlVisualSprite sprite,
    std::int16_t x = 10, std::int16_t width = 88,
    std::int16_t height = 38) {
    return {sprite, x, 13, width, height, compact_anchors};
}

constexpr std::array layouts{
    make_layout(ControlVisualSprite::keyboard),
    make_layout(ControlVisualSprite::generic_gamepad),
    make_layout(ControlVisualSprite::dualshock4),
    ControlHintLayout{ControlVisualSprite::dualsense,
        3, 13, 72, 39, dualsense_anchors},
    make_layout(ControlVisualSprite::xbox),
    make_layout(ControlVisualSprite::switch_pro_controller),
    make_layout(ControlVisualSprite::switch_single_joycon),
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

std::array<std::uint8_t, 5> mini_glyph(char value) noexcept {
    switch (value) {
    case 'A': return {2, 5, 7, 5, 5};
    case 'B': return {6, 5, 6, 5, 6};
    case 'C': return {3, 4, 4, 4, 3};
    case 'D': return {6, 5, 5, 5, 6};
    case 'E': return {7, 4, 6, 4, 7};
    case 'F': return {7, 4, 6, 4, 4};
    case 'H': return {5, 5, 7, 5, 5};
    case 'I': return {7, 2, 2, 2, 7};
    case 'K': return {5, 5, 6, 5, 5};
    case 'L': return {4, 4, 4, 4, 7};
    case 'M': return {5, 7, 7, 5, 5};
    case 'N': return {5, 7, 7, 7, 5};
    case 'O': return {2, 5, 5, 5, 2};
    case 'P': return {6, 5, 6, 4, 4};
    case 'R': return {6, 5, 6, 5, 5};
    case 'S': return {3, 4, 2, 1, 6};
    case 'T': return {7, 2, 2, 2, 2};
    case 'U': return {5, 5, 5, 5, 7};
    case 'V': return {5, 5, 5, 5, 2};
    case 'W': return {5, 5, 7, 7, 5};
    case 'X': return {5, 5, 2, 5, 5};
    case '+': return {0, 2, 7, 2, 0};
    case '-': return {0, 0, 7, 0, 0};
    case '/': return {1, 1, 2, 4, 4};
    case '[': return {6, 4, 4, 4, 6};
    case ']': return {3, 1, 1, 1, 3};
    case '^': return {2, 5, 0, 0, 0};
    default: return {};
    }
}

std::int32_t measure_mini_text(std::string_view text) noexcept {
    return text.empty() ? 0 : static_cast<std::int32_t>(text.size() * 4U - 1U);
}

void draw_mini_text(render::Framebuffer& target, std::string_view text,
    std::int32_t x, std::int32_t y, std::uint8_t colour) noexcept {
    for (const auto character : text) {
        const auto glyph = mini_glyph(character);
        for (auto row = 0; row < 5; ++row) {
            for (auto column = 0; column < 3; ++column) {
                if ((glyph[static_cast<std::size_t>(row)]
                        & (1U << (2 - column))) != 0U) {
                    target.set(x + column, y + row, colour);
                }
            }
        }
        x += 4;
    }
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

void draw_dualsense(render::Framebuffer& target,
    const ControlHintLayout& layout, std::int32_t origin_x,
    std::int32_t origin_y,
    std::span<const render::Rgba8, 256> palette,
    const std::array<std::uint16_t, 256>& cgram) noexcept {
    const auto x = origin_x + layout.sprite_x;
    const auto y = origin_y + layout.sprite_y;
    static_assert(dualsense_pixel_art_rgba_len == 72U * 48U * 4U);
    static std::array<std::uint16_t, 256> cached_cgram{};
    static std::array<std::uint8_t, 72U * 48U> mapped_pixels{};
    static bool cache_ready{};
    if (!cache_ready || cached_cgram != cgram) {
        cached_cgram = cgram;
        cache_ready = true;
        for (std::size_t pixel = 0; pixel < mapped_pixels.size(); ++pixel) {
            const auto offset = pixel * 4U;
            const auto red = dualsense_pixel_art_rgba[offset];
            const auto green = dualsense_pixel_art_rgba[offset + 1U];
            const auto blue = dualsense_pixel_art_rgba[offset + 2U];
            std::uint8_t colour{};
            auto closest_distance = std::numeric_limits<std::uint32_t>::max();
            for (std::size_t index = 0; index < palette.size(); ++index) {
                const auto delta_r = static_cast<std::int32_t>(red)
                    - palette[index].r;
                const auto delta_g = static_cast<std::int32_t>(green)
                    - palette[index].g;
                const auto delta_b = static_cast<std::int32_t>(blue)
                    - palette[index].b;
                const auto distance = static_cast<std::uint32_t>(
                    delta_r * delta_r * 3 + delta_g * delta_g * 6
                    + delta_b * delta_b * 2);
                if (distance < closest_distance) {
                    closest_distance = distance;
                    colour = static_cast<std::uint8_t>(index);
                }
            }
            mapped_pixels[pixel] = colour;
        }
    }
    for (std::size_t pixel = 0; pixel < 72U * 48U; ++pixel) {
        const auto offset = pixel * 4U;
        const auto alpha = dualsense_pixel_art_rgba[offset + 3U];
        if (alpha < 96U) continue;
        target.set(x + static_cast<std::int32_t>(pixel % 72U),
            y + static_cast<std::int32_t>(pixel / 72U),
            mapped_pixels[pixel]);
    }
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

std::int32_t measure_control_mini_text(std::string_view text) noexcept {
    return measure_mini_text(text);
}

void draw_control_mini_text(render::Framebuffer& framebuffer,
    std::string_view text, std::int32_t x, std::int32_t y,
    std::uint8_t colour) noexcept {
    draw_mini_text(framebuffer, text, x, y, colour);
}

ControlVisualProfile detect_control_visual_profile(
    const ControlDetectionInput& input) noexcept {
    if (input.platform == ControlPlatform::switch_console) {
        if (input.handheld) return ControlVisualProfile::switch_handheld;
        if (input.device == ControlDeviceKind::switch_single_joycon) {
            return ControlVisualProfile::switch_single_joycon;
        }
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
    case ControlDeviceKind::switch_single_joycon:
        return ControlVisualProfile::switch_single_joycon;
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
    // STARFOX_SWITCH_PROFILE_ASSIGNMENT_PASS02
    input.handheld =
        appletGetOperationMode()
        == AppletOperationMode_Handheld;


    if (!input.handheld) {

        const auto style =
            hidGetNpadStyleSet(
                HidNpadIdType_No1);


        const auto assignment =
            hidGetNpadJoyAssignment(
                HidNpadIdType_No1);


        const auto single_style =
            (
                style
                & (
                    HidNpadStyleTag_NpadJoyLeft
                    | HidNpadStyleTag_NpadJoyRight
                )
            ) != 0U;


        // Assignment mode is useful during the transition from a
        // paired set to one horizontal Joy-Con, where style bits
        // can briefly overlap.
        if (assignment
                == HidNpadJoyAssignmentMode_Single
            && single_style) {

            input.device =
                ControlDeviceKind::
                    switch_single_joycon;

        } else if (
            (
                style
                & HidNpadStyleTag_NpadJoyDual
            ) != 0U) {

            input.device =
                ControlDeviceKind::
                    switch_dual_joycon;

        } else if (single_style) {

            input.device =
                ControlDeviceKind::
                    switch_single_joycon;
        }
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
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT:
    case SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT:
        kind = ControlDeviceKind::switch_single_joycon; break;
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
    case ControlVisualProfile::switch_single_joycon:
        return switch_single_joycon_bindings;
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
        "XBOX", "SWITCH PRO", "JOY-CON", "DUAL JOY-CON", "HANDHELD"};
    return names[profile_index(profile)];
}

void draw_control_visual_profile(ControlVisualProfile profile,
    render::Framebuffer& framebuffer,
    const render::ScaledTextRenderer& text_renderer,
    std::int32_t viewport_origin,
    const std::array<std::uint16_t, 256>& cgram) noexcept {
    constexpr std::uint8_t body = 4U;
    constexpr std::uint8_t outline = 14U;
    constexpr std::uint8_t accent = 7U;
    // Replace CONT.SCR's original SNES controller and callouts in-place.
    // Sampling the unobstructed backdrop keeps this host overlay compatible
    // with every palette variant instead of assuming a fixed colour index.
    // Coordinates here are cartridge-space coordinates; viewport_origin is
    // added below exactly once for widescreen presentation.
    constexpr auto panel_x = 13;
    constexpr auto panel_y = 118;
    constexpr auto panel_width = 145;
    constexpr auto panel_height = 91;
    constexpr auto content_width = 113;
    const auto x = panel_x + viewport_origin;
    const auto& layout = control_hint_layout(profile);
    const auto palette = render::decode_bgr555_palette(cgram);
    const auto backdrop = framebuffer.get(
        static_cast<std::uint32_t>(5 + viewport_origin), 210U);
    fill_rect(framebuffer, x, panel_y, panel_width, panel_height, backdrop);
    // STARFOX_HD_PROFILE_PANEL_ONLY_PASS05
    //
    // These profiles use their QOI artwork in the SDL presentation
    // pass. Keep only the cleaned cartridge panel underneath.
    if (profile == ControlVisualProfile::dualsense
        || profile == ControlVisualProfile::dualshock4
        || profile == ControlVisualProfile::xbox
        || profile == ControlVisualProfile::switch_pro_controller
        || profile == ControlVisualProfile::switch_single_joycon
        || profile == ControlVisualProfile::switch_dual_joycon
        || profile == ControlVisualProfile::switch_handheld) {

        return;
    }
    const auto title = control_visual_profile_name(profile);
    static_cast<void>(text_renderer);
    draw_mini_text(framebuffer, title,
        x + content_width / 2 - measure_mini_text(title) / 2,
        panel_y + 3, outline);

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
    case ControlVisualSprite::dualsense:
        draw_dualsense(framebuffer, layout, x, panel_y, palette, cgram);
        break;
    default:
        draw_gamepad(framebuffer, layout, x, panel_y, body, outline, accent, false);
        break;
    }

    const auto& labels = control_hint_bindings(profile);
    for (const auto& anchor : layout.anchors) {
        if (anchor.action == ControlHintAction::start
            || anchor.action == ControlHintAction::select) {
            continue;
        }
        draw_mini_text(framebuffer, label_for(labels, anchor.action),
            x + anchor.x, panel_y + anchor.y, outline);
    }
}

} // namespace starfox::app
