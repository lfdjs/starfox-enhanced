#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"
BUILD_DIR="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-runtime-video-fix/$STAMP"

mkdir -p "$REPORT_DIR"

cp -a "$SOURCE" "$REPORT_DIR/starfox_pc.cpp.before"

export SOURCE

python3 <<'PY'
from pathlib import Path
import os

path = Path(os.environ["SOURCE"])
text = path.read_text(encoding="utf-8")

# ============================================================
# libnx
# ============================================================

old = '''#include <SDL3/SDL.h>

#include <algorithm>
'''

new = '''#include <SDL3/SDL.h>

#if defined(STARFOX_SWITCH_RUNTIME)
#include <switch.h>
#endif

#include <algorithm>
'''

if new not in text:
    if old not in text:
        raise RuntimeError("include SDL3 esperado não encontrado")

    text = text.replace(old, new, 1)

    print("PATCH   include <switch.h>")
else:
    print("JA OK   include <switch.h>")


# ============================================================
# Debug guest -> Ryubing
# ============================================================

anchor = '''using starfox::input::ButtonMask;

'''

helper = '''using starfox::input::ButtonMask;

#if defined(STARFOX_SWITCH_RUNTIME)
void switch_runtime_debug(std::string_view message) noexcept {
    svcOutputDebugString(
        message.data(),
        message.size());
}

void switch_runtime_debug_sdl(std::string_view stage) {
    std::string message{
        "[SFE SWITCH] "};

    message += stage;
    message += ": ";
    message += SDL_GetError();
    message += "\\n";

    switch_runtime_debug(message);
}
#endif

'''

if helper not in text:
    if anchor not in text:
        raise RuntimeError("namespace inicial não encontrado")

    text = text.replace(anchor, helper, 1)

    print("PATCH   debug libnx")
else:
    print("JA OK   debug libnx")


# ============================================================
# SDL Init checkpoints
# ============================================================

old = '''class SdlContext {
public:
    SdlContext() {
        starfox::app::configure_native_gamepad_support();
        if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD | SDL_INIT_AUDIO)) {
            throw std::runtime_error{std::string{"SDL_Init: "} + SDL_GetError()};
        }
    }
'''

new = '''class SdlContext {
public:
    SdlContext() {
#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] before configure_native_gamepad_support\\n");
#endif

        starfox::app::configure_native_gamepad_support();

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] before SDL_Init VIDEO+GAMEPAD+AUDIO\\n");
#endif

        if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD | SDL_INIT_AUDIO)) {
#if defined(STARFOX_SWITCH_RUNTIME)
            switch_runtime_debug_sdl("SDL_Init FAILED");
#endif
            throw std::runtime_error{std::string{"SDL_Init: "} + SDL_GetError()};
        }

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] SDL_Init VIDEO+GAMEPAD+AUDIO OK\\n");
#endif
    }
'''

if new not in text:
    if old not in text:
        raise RuntimeError("SdlContext esperado não encontrado")

    text = text.replace(old, new, 1)

    print("PATCH   checkpoints SDL_Init")
else:
    print("JA OK   checkpoints SDL_Init")


# ============================================================
# Window Switch
# ============================================================

start = text.find('class Window {\npublic:\n    Window() {')

if start < 0:
    raise RuntimeError("class Window não encontrada")

constructor_end_marker = '''    ~Window() {
'''

end = text.find(constructor_end_marker, start)

if end < 0:
    raise RuntimeError("destrutor de Window não encontrado")

old_constructor = text[start:end]

new_constructor = r'''class Window {
public:
    Window() {
#if defined(STARFOX_SWITCH_RUNTIME)

        constexpr auto window_title =
            "Star Fox Enhanced";

        constexpr auto window_width =
            1280;

        constexpr auto window_height =
            720;

        switch_runtime_debug(
            "[SFE SWITCH] Window constructor entered\n");

        // Use exactly the video path validated by
        // starfox_switch_sdl_probe:
        //
        // fullscreen OpenGL window
        //        ↓
        // explicit opengles2 renderer
        //        ↓
        // switch-mesa / EGL / libnx NWindow
        //
        // Do not use SDL_CreateWindowAndRenderer here because
        // its automatic renderer/window negotiation differs from
        // the path already proven on Switch/Ryubing.

        switch_runtime_debug(
            "[SFE SWITCH] before SDL_CreateWindow OPENGL\n");

        window_ = SDL_CreateWindow(
            window_title,
            window_width,
            window_height,
            SDL_WINDOW_FULLSCREEN
                | SDL_WINDOW_OPENGL);

        if (window_ == nullptr) {
            switch_runtime_debug_sdl(
                "SDL_CreateWindow FAILED");

            throw std::runtime_error{
                std::string{"SDL_CreateWindow: "}
                + SDL_GetError()};
        }

        switch_runtime_debug(
            "[SFE SWITCH] SDL_CreateWindow OK\n");

        switch_runtime_debug(
            "[SFE SWITCH] before SDL_CreateRenderer(opengles2)\n");

        renderer_ = SDL_CreateRenderer(
            window_,
            "opengles2");

        if (renderer_ == nullptr) {
            switch_runtime_debug_sdl(
                "SDL_CreateRenderer FAILED");

            throw std::runtime_error{
                std::string{
                    "SDL_CreateRenderer(opengles2): "}
                + SDL_GetError()};
        }

        switch_runtime_debug(
            "[SFE SWITCH] SDL_CreateRenderer(opengles2) OK\n");

#else

        constexpr auto window_title =
            "Star Fox Enhanced - native PC runtime";

        constexpr auto window_width =
            1024;

        constexpr auto window_height =
            896;

        constexpr auto window_flags =
            SDL_WINDOW_RESIZABLE;

        if (!SDL_CreateWindowAndRenderer(
                window_title,
                window_width,
                window_height,
                window_flags,
                &window_,
                &renderer_)) {

            throw std::runtime_error{
                std::string{
                    "SDL_CreateWindowAndRenderer: "}
                + SDL_GetError()};
        }

        SDL_ShowWindow(window_);

        static_cast<void>(
            SDL_SyncWindow(window_));

        // Desktop presentation has its own exact 60 Hz schedule.
        // Do not follow a 75/120/144 Hz desktop display.
        SDL_SetRenderVSync(
            renderer_,
            0);

#endif

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] before logical presentation\n");
#endif

        SDL_SetRenderLogicalPresentation(
            renderer_,
            snes_width,
            snes_height,
            SDL_LOGICAL_PRESENTATION_LETTERBOX);

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] logical presentation OK\n");

        switch_runtime_debug(
            "[SFE SWITCH] before SDL_CreateTexture\n");
#endif

        texture_ = SDL_CreateTexture(
            renderer_,
            SDL_PIXELFORMAT_RGBA32,
            SDL_TEXTUREACCESS_STREAMING,
            snes_width,
            snes_height);

        if (texture_ == nullptr) {
#if defined(STARFOX_SWITCH_RUNTIME)
            switch_runtime_debug_sdl(
                "SDL_CreateTexture FAILED");
#endif

            throw std::runtime_error{
                std::string{"SDL_CreateTexture: "}
                + SDL_GetError()};
        }

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] SDL_CreateTexture OK\n");
#endif

        SDL_SetTextureScaleMode(
            texture_,
            SDL_SCALEMODE_NEAREST);

#if defined(STARFOX_SWITCH_RUNTIME)
        // The Switch EGL backend establishes swap interval 1 when
        // its GL context is created. Preserve that fixed 60 Hz path.
        // This intentionally differs from desktop.
        switch_runtime_debug(
            "[SFE SWITCH] preserving backend VSync\n");
#endif

        SDL_SetRenderDrawColor(
            renderer_,
            0,
            0,
            0,
            255);

        SDL_RenderClear(
            renderer_);

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] before first runtime present\n");
#endif

        SDL_RenderPresent(
            renderer_);

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] first runtime present OK\n");
#else
        static_cast<void>(
            SDL_SyncWindow(window_));
#endif
    }

'''

text = (
    text[:start]
    + new_constructor
    + text[end:]
)

path.write_text(text, encoding="utf-8")

print("PATCH   Window Switch usa caminho explícito GLES2")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

grep -n \
  -A120 \
  -B10 \
  'Window constructor entered' \
  src/app/starfox_pc.cpp \
  | head -n 150

echo
echo "============================================================"
echo "BUILD SWITCH"
echo "============================================================"

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

cmake \
  --build "$BUILD_DIR" \
  --target starfox_switch_nro \
  -j"$(nproc)" \
  --verbose \
  2>&1 \
  | tee "$REPORT_DIR/build.log"

NRO="$BUILD_DIR/ports/switch/starfox_switch.nro"

echo
echo "============================================================"
echo "NRO CHECK"
echo "============================================================"

ls -lh "$NRO"

grep -aob \
  'NRO0\|ASET' \
  "$NRO"

sha256sum "$NRO" \
  | tee "$REPORT_DIR/sha256.txt"

{
    echo "STAR FOX ENHANCED — SWITCH VIDEO PATH FIX"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/sha256.txt"
    echo
    echo "GIT STATUS:"
    git status --short
    echo
    echo "DIFF STAT:"
    git diff --stat
} > "$REPORT_DIR/report-share.txt"

echo
echo "============================================================"
echo "CONCLUÍDO"
echo "============================================================"
echo
echo "Novo NRO:"
echo "  $NRO"
echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
