# Nintendo Switch homebrew runtime

This target is separate from the Windows/Linux `starfox_pc` target. It shares
the deterministic game and renderer libraries, but builds its own
`starfox_switch.nro` entry point with a console-specific runtime profile.

The Switch profile always:

- presents at 60 FPS in handheld and docked modes;
- advances gameplay at the original deterministic 20 Hz logic frequency;
- starts at the cartridge title (`TITLEMAP`) instead of the host configuration
  screen;
- ignores the desktop pregame settings file; and
- uses a fullscreen 1280x720 SDL surface, which the system scales for the
  active display mode.

## Prerequisites

Install devkitPro's `switch-dev`, `switch-cmake`, `switch-pkg-config`, and an
SDL3 build with the libnx Nintendo Switch backend. SDL3 is not yet shipped as
a devkitPro pacman package, so install the maintained `devkitPro/SDL` Switch
branch into `$DEVKITPRO/portlibs/switch` first. The desktop SDL downloaded by
the root build is deliberately not cross-compiled.

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

The runtime presently uses SDL's unified gamepad mapping. Dynamic controller
art for single Joy-Con, paired Joy-Con, handheld, and Pro Controller is a
separate follow-up milestone; it requires libnx controller-style detection
and new original artwork.
