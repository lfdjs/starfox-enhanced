#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH SDL3/EGL PROBE"
echo "============================================================"

mkdir -p ports/switch

touch ports/switch/sdl_probe.cpp

cat > ports/switch/sdl_probe.cpp <<'CPP_EOF'
#include <SDL3/SDL.h>

#include <switch.h>

#include <cstdio>
#include <cstring>

namespace {

void debug_message(const char* message) {
    if (message == nullptr) {
        return;
    }

    svcOutputDebugString(
        message,
        std::strlen(message));
}

void debug_sdl_error(const char* stage) {
    char buffer[768]{};

    std::snprintf(
        buffer,
        sizeof(buffer),
        "[SFE SDL PROBE] %s FAILED: %s\n",
        stage,
        SDL_GetError());

    debug_message(buffer);
}

void debug_renderer_drivers() {
    const int count =
        SDL_GetNumRenderDrivers();

    char buffer[256]{};

    std::snprintf(
        buffer,
        sizeof(buffer),
        "[SFE SDL PROBE] renderer drivers: %d\n",
        count);

    debug_message(buffer);

    for (int index = 0;
         index < count;
         ++index) {

        const char* name =
            SDL_GetRenderDriver(index);

        std::snprintf(
            buffer,
            sizeof(buffer),
            "[SFE SDL PROBE] renderer[%d]=%s\n",
            index,
            name != nullptr ? name : "(null)");

        debug_message(buffer);
    }
}

} // namespace

int main() {
    debug_message(
        "[SFE SDL PROBE] main entered\n");

    SDL_SetHint(
        SDL_HINT_RENDER_DRIVER,
        "opengles2");

    debug_message(
        "[SFE SDL PROBE] before SDL_Init(VIDEO)\n");

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        debug_sdl_error("SDL_Init");
        return 10;
    }

    debug_message(
        "[SFE SDL PROBE] SDL_Init(VIDEO) OK\n");

    debug_renderer_drivers();

    debug_message(
        "[SFE SDL PROBE] before SDL_CreateWindow\n");

    SDL_Window* window =
        SDL_CreateWindow(
            "Star Fox Enhanced SDL Probe",
            1280,
            720,
            SDL_WINDOW_FULLSCREEN
                | SDL_WINDOW_OPENGL);

    if (window == nullptr) {
        debug_sdl_error(
            "SDL_CreateWindow");

        SDL_Quit();

        return 20;
    }

    debug_message(
        "[SFE SDL PROBE] SDL_CreateWindow OK\n");

    // Useful checkpoint: if Ryubing crashes after this message,
    // the failure occurs while creating the GLES2/EGL renderer.
    debug_message(
        "[SFE SDL PROBE] before SDL_CreateRenderer(opengles2)\n");

    SDL_Renderer* renderer =
        SDL_CreateRenderer(
            window,
            "opengles2");

    if (renderer == nullptr) {
        debug_sdl_error(
            "SDL_CreateRenderer(opengles2)");

        SDL_DestroyWindow(window);
        SDL_Quit();

        return 30;
    }

    debug_message(
        "[SFE SDL PROBE] SDL_CreateRenderer(opengles2) OK\n");

    if (!SDL_SetRenderDrawColor(
            renderer,
            16,
            32,
            64,
            255)) {

        debug_sdl_error(
            "SDL_SetRenderDrawColor");
    }

    debug_message(
        "[SFE SDL PROBE] before first present\n");

    bool running = true;

    for (int frame = 0;
         frame < 300 && running;
         ++frame) {

        SDL_Event event{};

        while (SDL_PollEvent(&event)) {
            if (event.type
                == SDL_EVENT_QUIT) {

                running = false;
            }
        }

        if (!SDL_RenderClear(renderer)) {
            debug_sdl_error(
                "SDL_RenderClear");

            break;
        }

        if (!SDL_RenderPresent(renderer)) {
            debug_sdl_error(
                "SDL_RenderPresent");

            break;
        }

        if (frame == 0) {
            debug_message(
                "[SFE SDL PROBE] first present OK\n");
        }

        if (frame == 60) {
            debug_message(
                "[SFE SDL PROBE] 60 frames OK\n");
        }

        if (frame == 180) {
            debug_message(
                "[SFE SDL PROBE] 180 frames OK\n");
        }

        SDL_Delay(16);
    }

    debug_message(
        "[SFE SDL PROBE] shutting down normally\n");

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);

    SDL_Quit();

    return 0;
}
CPP_EOF

if ! grep -q \
    'starfox_switch_sdl_probe' \
    ports/switch/CMakeLists.txt
then

cat >> ports/switch/CMakeLists.txt <<'CMAKE_EOF'

# ------------------------------------------------------------
# SDL3 / EGL diagnostic NRO
# ------------------------------------------------------------

add_executable(
    starfox_switch_sdl_probe
    EXCLUDE_FROM_ALL
    ${CMAKE_CURRENT_SOURCE_DIR}/sdl_probe.cpp)

target_compile_definitions(
    starfox_switch_sdl_probe
    PRIVATE
        __SWITCH__=1)

target_link_libraries(
    starfox_switch_sdl_probe
    PRIVATE
        SDL3::SDL3)

set(
    switch_sdl_probe_nacp
    "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch_sdl_probe.nacp")

set(
    switch_sdl_probe_nro
    "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch_sdl_probe.nro")

add_custom_command(
    OUTPUT
        "${switch_sdl_probe_nacp}"

    COMMAND
        "${STARFOX_NACPTOOL}"
        --create
        "Star Fox SDL Probe"
        "Star Fox Enhanced contributors"
        "${PROJECT_VERSION}"
        "${switch_sdl_probe_nacp}"

    VERBATIM)

add_custom_command(
    OUTPUT
        "${switch_sdl_probe_nro}"

    COMMAND
        "${STARFOX_ELF2NRO}"
        "$<TARGET_FILE:starfox_switch_sdl_probe>"
        "${switch_sdl_probe_nro}"
        "--nacp=${switch_sdl_probe_nacp}"

    DEPENDS
        starfox_switch_sdl_probe
        "${switch_sdl_probe_nacp}"

    VERBATIM)

add_custom_target(
    starfox_switch_sdl_probe_nro
    DEPENDS
        "${switch_sdl_probe_nro}")
CMAKE_EOF

    echo "CMake probe adicionado."
else
    echo "CMake probe já existe."
fi

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

echo
echo "Configurando..."

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

"$DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake" \
    -S . \
    -B "$BUILD_DIR" \
    -DSTARFOX_BUILD_RUNTIME=OFF \
    -DSTARFOX_BUILD_TESTS=OFF \
    -DSTARFOX_BUILD_SWITCH=ON \
    -DCMAKE_BUILD_TYPE=Release

echo
echo "============================================================"
echo "BUILD PROBE"
echo "============================================================"

cmake \
    --build "$BUILD_DIR" \
    --target starfox_switch_sdl_probe_nro \
    -j"$(nproc)" \
    --verbose

PROBE="$BUILD_DIR/ports/switch/starfox_switch_sdl_probe.nro"

echo
echo "============================================================"
echo "NRO"
echo "============================================================"

ls -lh "$PROBE"

echo
grep -aob \
    'NRO0\|ASET' \
    "$PROBE"

echo
echo "Probe pronto:"
echo
echo "  $PROBE"
