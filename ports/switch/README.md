# Nintendo Switch homebrew runtime

This target is separate from the Windows/Linux `starfox_pc` target. It shares
the deterministic game and renderer libraries, but builds its own
`starfox_switch.nro` entry point with a console-specific runtime profile.

The Switch profile always:

- presents at 60 FPS in handheld and docked modes;
- advances gameplay at the deterministic 20 Hz logic frequency;
- starts from the cartridge boot sequence (`BOOT`), including the original
  Nintendo Presents sequence before the title screen;
- uses the Original experience;
- defaults to the 16:9 widescreen renderer;
- uses English as the production language while PT-BR remains incomplete;
- ignores the desktop pregame settings file; and
- uses a fullscreen 1280x720 SDL surface, which the system scales for the
  active display mode.

## Prerequisites

Install devkitPro's `switch-dev`, `switch-cmake`, `switch-pkg-config`,
`switch-mesa`, and `switch-libdrm_nouveau`, plus an SDL3 build with a libnx
Nintendo Switch backend. SDL3 is not yet shipped as a devkitPro pacman
package. The currently validated combination is SDL 3.4.14 commit
`147a8ee32dbf9ac02f3794964490687b6bbda1bc` with the
[`sdl3-switch`](https://github.com/neomody77/sdl3-switch) patch at commit
`182e511214d7600e4bdab8606d7caf0ef744afd6`. Install its static library,
headers, pkg-config file, and CMake package configuration into
`$DEVKITPRO/portlibs/switch`. The desktop SDL downloaded by the root build is
deliberately not cross-compiled.

## Build

```sh
export DEVKITPRO=/opt/devkitpro

$DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake \
  -S . -B build-switch \
  -DSTARFOX_BUILD_RUNTIME=OFF \
  -DSTARFOX_BUILD_TESTS=OFF \
  -DSTARFOX_BUILD_SWITCH=ON \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build-switch --target starfox_switch_nro -j
```

Copy `build-switch/ports/switch/starfox_switch.nro`, `SF.SFC`, `SYMBOLS.TXT`,
and the `localization` directory to `sdmc:/switch/starfox-enhanced/`. ROM data
is user-supplied and is never included in the NRO.

The runtime uses SDL's unified gamepad mapping together with a libnx-native
Player 1 fallback. The native path maps Plus directly to SNES Start, Minus to
Select, the Switch face-button diamond to the equivalent SNES buttons, and
accepts both D-pad and left stick movement. This keeps console input independent
from emulator-specific SDL mapping while remaining compatible with real Switch
hardware.

Dynamic controller art for single Joy-Con, paired Joy-Con, handheld, and Pro
Controller remains a separate follow-up milestone.
