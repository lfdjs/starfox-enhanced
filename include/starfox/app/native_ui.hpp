#pragma once

#include "starfox/app/control_visual_profile.hpp"

#include <SDL3/SDL.h>

#include <cstdint>
#include <span>

namespace starfox::app {

struct NativeControlsUiModel {
    ControlVisualProfile profile{
        ControlVisualProfile::generic_gamepad_pc};

    std::uint8_t control_type{};
    std::uint8_t brightness{15U};
};

// Renders CONT.SCR directly in the current physical render output.
//
// The cartridge framebuffer remains the authoritative source for the animated
// Arwing preview, while the surrounding interface is resolution-independent.
[[nodiscard]]
bool render_native_controls_ui(
    SDL_Renderer* renderer,
    SDL_Texture* cartridge_texture,
    std::uint32_t cartridge_width,
    std::uint32_t cartridge_height,
    SDL_Texture* controller_texture,
    const SDL_FRect& controller_source,
    const NativeControlsUiModel& model) noexcept;

// STARFOX_NATIVE_TITLE_UI_PASS07
//
// Remastered title presentation. The cartridge title framebuffer remains
// authoritative for animated/logo artwork; Native UI owns framing and
// high-resolution prompts.

[[nodiscard]]
bool render_native_title_ui(
    SDL_Renderer* renderer,
    SDL_Texture* cartridge_texture,
    std::uint32_t cartridge_width,
    std::uint32_t cartridge_height,
    std::span<const std::uint8_t> rgba_pixels,
    std::uint8_t brightness) noexcept;


} // namespace starfox::app
