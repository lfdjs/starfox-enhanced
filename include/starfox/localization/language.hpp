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

    hud_score,
    hud_total,
    hud_team,
    hud_down,
    hud_pause,
    hud_enemy,
    hud_shield,

    count,
};

[[nodiscard]] std::string_view text(
    Language language,
    TextId id) noexcept;

[[nodiscard]] std::string_view language_name(
    Language language) noexcept;

} // namespace starfox::localization
