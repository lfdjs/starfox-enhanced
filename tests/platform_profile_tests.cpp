#include "starfox/app/platform_profile.hpp"

#include <cassert>

int main() {
    constexpr auto desktop = starfox::app::desktop_runtime_profile();
    static_assert(desktop.initial_map == "BOOT");
    static_assert(!desktop.bypass_host_pregame_menu);
    static_assert(desktop.persist_host_pregame_settings);

    constexpr auto console = starfox::app::switch_runtime_profile();
    static_assert(console.initial_map == "TITLEMAP");
    static_assert(console.bypass_host_pregame_menu);
    static_assert(!console.persist_host_pregame_settings);
    static_assert(console.presentation_fps == 60U);
    static_assert(console.timing_mode
        == starfox::simulation::TimingMode::unlocked_20_fps);
    static_assert(console.display_mode
        == starfox::simulation::DisplayMode::standard_4_3);
    assert(true);
}
