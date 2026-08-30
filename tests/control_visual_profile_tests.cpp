#include "starfox/app/control_visual_profile.hpp"

#include <cassert>

using namespace starfox::app;

int main() {
    assert(detect_control_visual_profile({})
        == ControlVisualProfile::keyboard_pc);
    assert(detect_control_visual_profile({ControlPlatform::pc,
        ControlDeviceKind::generic_gamepad, false})
        == ControlVisualProfile::generic_gamepad_pc);
    assert(detect_control_visual_profile({ControlPlatform::pc,
        ControlDeviceKind::xbox, false}) == ControlVisualProfile::xbox);
    assert(detect_control_visual_profile({ControlPlatform::pc,
        ControlDeviceKind::dualshock4, false})
        == ControlVisualProfile::dualshock4);
    assert(detect_control_visual_profile({ControlPlatform::pc,
        ControlDeviceKind::dualsense, false})
        == ControlVisualProfile::dualsense);
    assert(detect_control_visual_profile({ControlPlatform::switch_console,
        ControlDeviceKind::none, false})
        == ControlVisualProfile::switch_pro_controller);
    assert(detect_control_visual_profile({ControlPlatform::switch_console,
        ControlDeviceKind::switch_dual_joycon, false})
        == ControlVisualProfile::switch_dual_joycon);
    assert(detect_control_visual_profile({ControlPlatform::switch_console,
        ControlDeviceKind::switch_pro_controller, true})
        == ControlVisualProfile::switch_handheld);

    assert(control_hint_bindings(ControlVisualProfile::keyboard_pc).fire
        == "Z FIRE");
    assert(control_hint_bindings(ControlVisualProfile::xbox).fire == "A FIRE");
    assert(control_hint_bindings(ControlVisualProfile::dualshock4).bomb
        == "O BOMB");
    assert(control_hint_bindings(ControlVisualProfile::dualsense).boost
        == "[] BOOST");
    assert(control_hint_bindings(
        ControlVisualProfile::switch_pro_controller).start == "+ START");
    assert(control_hint_bindings(
        ControlVisualProfile::switch_dual_joycon).bomb == "A BOMB");
    assert(control_hint_layout(ControlVisualProfile::switch_handheld).sprite
        == ControlVisualSprite::switch_handheld);
}
