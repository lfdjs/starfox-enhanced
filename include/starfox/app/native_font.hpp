#pragma once

#include <SDL3/SDL.h>

#include <cstdint>
#include <string_view>

namespace starfox::app {

[[nodiscard]]
float measure_native_ui_text(
    std::string_view text,
    float pixel_height) noexcept;


void draw_native_ui_text(
    SDL_Renderer* renderer,
    std::string_view text,
    float x,
    float y,
    float pixel_height,
    std::uint8_t red,
    std::uint8_t green,
    std::uint8_t blue,
    std::uint8_t alpha,
    std::uint8_t brightness) noexcept;


void shutdown_native_ui_font(
    SDL_Renderer* renderer) noexcept;

} // namespace starfox::app
