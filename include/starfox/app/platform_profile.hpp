#pragma once

#include "starfox/simulation/game_simulation.hpp"

#include <cstdint>
#include <string_view>

namespace starfox::app {

struct RuntimePlatformProfile {
    std::string_view initial_map{"BOOT"};
    simulation::TimingMode timing_mode{
        simulation::TimingMode::unlocked_20_fps};
    std::uint16_t presentation_fps{60U};
    simulation::DisplayMode display_mode{
        simulation::DisplayMode::standard_4_3};
    bool bypass_host_pregame_menu{};
    bool persist_host_pregame_settings{true};
};

[[nodiscard]] constexpr RuntimePlatformProfile desktop_runtime_profile() {
    return {};
}

[[nodiscard]] constexpr RuntimePlatformProfile switch_runtime_profile() {
    return {
        "TITLEMAP",
        simulation::TimingMode::unlocked_20_fps,
        60U,
        simulation::DisplayMode::standard_4_3,
        true,
        false,
    };
}

[[nodiscard]] constexpr RuntimePlatformProfile runtime_platform_profile() {
#if defined(STARFOX_SWITCH_RUNTIME)
    return switch_runtime_profile();
#else
    return desktop_runtime_profile();
#endif
}

inline void apply_runtime_platform_profile(
    simulation::GameSimulation& game,
    const RuntimePlatformProfile& profile = runtime_platform_profile()) {
    game.set_timing_mode(profile.timing_mode);
    game.set_presentation_fps(profile.presentation_fps);
    game.set_display_mode(profile.display_mode);
}

} // namespace starfox::app
