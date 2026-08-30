#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf03-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass03/$STAMP"

mkdir -p \
    "$REPORT_DIR/backup/include/starfox/app" \
    "$REPORT_DIR/backup/src/render" \
    "$REPORT_DIR/backup/src/app" \
    "$REPORT_DIR/backup/ports/switch"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 03"
echo "INTERNAL FRAME PROFILER"
echo "============================================================"
echo

FILES=(
    src/render/background_renderer.cpp
    src/render/sprite_renderer.cpp
    src/render/software_renderer.cpp
    src/app/starfox_pc.cpp
    ports/switch/CMakeLists.txt
)

for file in "${FILES[@]}"
do
    if [[ ! -f "$file" ]]
    then
        echo "ERRO: arquivo ausente:"
        echo "  $file"
        exit 10
    fi

    mkdir -p \
        "$REPORT_DIR/backup/$(dirname "$file")"

    cp -a \
        "$file" \
        "$REPORT_DIR/backup/$file"
done

if [[ -f include/starfox/app/perf_profiler.hpp ]]
then
    cp -a \
        include/starfox/app/perf_profiler.hpp \
        "$REPORT_DIR/backup/include/starfox/app/perf_profiler.hpp"
fi

mkdir -p include/starfox/app

touch include/starfox/app/perf_profiler.hpp

cat > include/starfox/app/perf_profiler.hpp <<'HPP_EOF'
#pragma once

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdio>

#if defined(STARFOX_PERF_SWITCH)
#include <switch.h>
#endif

namespace starfox::app::perf {

enum class Bucket : std::size_t {
    background,
    objects,
    software_3d,
    present,
    history,

    count,
};

inline constexpr std::size_t bucket_count =
    static_cast<std::size_t>(
        Bucket::count);

using Clock =
    std::chrono::steady_clock;

using Nanoseconds =
    std::chrono::nanoseconds;

inline std::array<std::uint64_t, bucket_count>
    frame_time_ns{};

inline std::array<std::uint64_t, bucket_count>
    frame_calls{};

inline std::array<std::uint64_t, bucket_count>
    accumulated_time_ns{};

inline std::array<std::uint64_t, bucket_count>
    accumulated_calls{};

inline Clock::time_point frame_begin{};
inline std::uint64_t accumulated_total_ns{};
inline std::uint64_t accumulated_frames{};

inline constexpr bool enabled() noexcept {
#if defined(STARFOX_PERF_PROFILER)
    return true;
#else
    return false;
#endif
}

inline void emit(
    const char* text,
    std::size_t size) noexcept {

#if defined(STARFOX_PERF_SWITCH)

    svcOutputDebugString(
        text,
        size);

#else

    std::fwrite(
        text,
        1U,
        size,
        stderr);

    std::fflush(
        stderr);

#endif
}

inline void begin_frame() noexcept {
    if (!enabled()) {
        return;
    }

    frame_time_ns.fill(0U);
    frame_calls.fill(0U);

    frame_begin =
        Clock::now();
}

inline void add(
    Bucket bucket,
    std::uint64_t nanoseconds) noexcept {

    if (!enabled()) {
        return;
    }

    const auto index =
        static_cast<std::size_t>(
            bucket);

    frame_time_ns[index] +=
        nanoseconds;

    ++frame_calls[index];
}

class ScopedTimer {
public:
    explicit ScopedTimer(
        Bucket bucket) noexcept
        : bucket_{bucket},
          begin_{Clock::now()} {
    }

    ~ScopedTimer() noexcept {
        if (!enabled()) {
            return;
        }

        const auto finish =
            Clock::now();

        const auto elapsed =
            std::chrono::duration_cast<
                Nanoseconds>(
                    finish - begin_);

        add(
            bucket_,
            static_cast<std::uint64_t>(
                elapsed.count()));
    }

    ScopedTimer(
        const ScopedTimer&) = delete;

    ScopedTimer& operator=(
        const ScopedTimer&) = delete;

private:
    Bucket bucket_;
    Clock::time_point begin_;
};

inline double milliseconds(
    std::uint64_t ns) noexcept {

    return static_cast<double>(ns)
        / 1'000'000.0;
}

inline void end_frame() noexcept {
    if (!enabled()) {
        return;
    }

    const auto now =
        Clock::now();

    const auto total =
        static_cast<std::uint64_t>(
            std::chrono::duration_cast<
                Nanoseconds>(
                    now - frame_begin)
                .count());

    accumulated_total_ns +=
        total;

    ++accumulated_frames;

    for (std::size_t index = 0U;
         index < bucket_count;
         ++index) {

        accumulated_time_ns[index] +=
            frame_time_ns[index];

        accumulated_calls[index] +=
            frame_calls[index];
    }

    // Report approximately once per second at the target 60 Hz.
    constexpr std::uint64_t report_frames =
        60U;

    if (accumulated_frames
        < report_frames) {

        return;
    }

    const auto frames =
        static_cast<double>(
            accumulated_frames);

    const auto average =
        [frames](std::uint64_t ns) {
            return milliseconds(ns)
                / frames;
        };

    const auto calls =
        [frames](std::uint64_t value) {
            return static_cast<double>(
                value)
                / frames;
        };

    const auto bg =
        static_cast<std::size_t>(
            Bucket::background);

    const auto obj =
        static_cast<std::size_t>(
            Bucket::objects);

    const auto gfx3d =
        static_cast<std::size_t>(
            Bucket::software_3d);

    const auto present =
        static_cast<std::size_t>(
            Bucket::present);

    const auto history =
        static_cast<std::size_t>(
            Bucket::history);

    std::uint64_t measured{};

    for (const auto value :
         accumulated_time_ns) {

        measured += value;
    }

    const auto other =
        accumulated_total_ns
            > measured
        ? accumulated_total_ns
            - measured
        : 0U;

    const auto total_ms =
        average(
            accumulated_total_ns);

    const auto estimated_fps =
        total_ms > 0.0
        ? 1'000.0 / total_ms
        : 0.0;

    char line[1024]{};

    const auto length =
        std::snprintf(
            line,
            sizeof(line),

            "[SFE PERF] "
            "fps=%.2f "
            "total=%.3fms "
            "bg=%.3fms "
            "obj=%.3fms "
            "3d=%.3fms "
            "present=%.3fms "
            "history=%.3fms "
            "other=%.3fms "
            "calls(bg/obj/3d)=%.1f/%.1f/%.1f\n",

            estimated_fps,
            total_ms,

            average(
                accumulated_time_ns[bg]),

            average(
                accumulated_time_ns[obj]),

            average(
                accumulated_time_ns[gfx3d]),

            average(
                accumulated_time_ns[present]),

            average(
                accumulated_time_ns[history]),

            average(other),

            calls(
                accumulated_calls[bg]),

            calls(
                accumulated_calls[obj]),

            calls(
                accumulated_calls[gfx3d]));

    if (length > 0) {

        emit(
            line,
            static_cast<std::size_t>(
                length));
    }

    accumulated_total_ns = 0U;
    accumulated_frames = 0U;

    accumulated_time_ns.fill(0U);
    accumulated_calls.fill(0U);
}

} // namespace starfox::app::perf
HPP_EOF

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])

include_line = (
    '#include "starfox/app/perf_profiler.hpp"\n'
)


def ensure_include(path):
    text = path.read_text(
        encoding="utf-8"
    )

    if include_line in text:
        return text

    first_include = text.find("#include ")

    if first_include < 0:
        raise RuntimeError(
            f"Nenhum include encontrado em {path}"
        )

    return (
        text[:first_include]
        + include_line
        + text[first_include:]
    )


def insert_function_timer(
    text,
    signature,
    bucket,
    description):

    marker = (
        f"perf_timer_{bucket}"
    )

    start = text.find(signature)

    if start < 0:
        raise RuntimeError(
            f"Função não encontrada: "
            f"{description}"
        )

    # If this specific function was already instrumented,
    # do not insert it again.
    next_function = text.find(
        "\nvoid ",
        start + len(signature)
    )

    section_end = (
        len(text)
        if next_function < 0
        else next_function
    )

    section = text[
        start:section_end
    ]

    if marker in section:
        print(
            f"JA OK   {description}"
        )
        return text

    brace = text.find(
        "{",
        start
    )

    if brace < 0:
        raise RuntimeError(
            f"Corpo não encontrado: "
            f"{description}"
        )

    insertion = f'''
    starfox::app::perf::ScopedTimer
        {marker}{{
            starfox::app::perf::Bucket::{bucket}}};
'''

    text = (
        text[:brace + 1]
        + insertion
        + text[brace + 1:]
    )

    print(
        f"PATCH   {description}"
    )

    return text


# ============================================================
# BackgroundRenderer
# ============================================================

path = root / "src/render/background_renderer.cpp"

text = ensure_include(path)

text = insert_function_timer(
    text,
    "void BackgroundRenderer::draw_bg1(",
    "background",
    "BackgroundRenderer::draw_bg1"
)

text = insert_function_timer(
    text,
    "void BackgroundRenderer::draw_bg2(",
    "background",
    "BackgroundRenderer::draw_bg2"
)

text = insert_function_timer(
    text,
    "void BackgroundRenderer::draw_bg3(",
    "background",
    "BackgroundRenderer::draw_bg3"
)

path.write_text(
    text,
    encoding="utf-8"
)


# ============================================================
# SpriteRenderer
# ============================================================

path = root / "src/render/sprite_renderer.cpp"

text = ensure_include(path)

text = insert_function_timer(
    text,
    "void SpriteRenderer::draw_objects(",
    "objects",
    "SpriteRenderer::draw_objects"
)

text = insert_function_timer(
    text,
    "void SpriteRenderer::draw_meters(",
    "objects",
    "SpriteRenderer::draw_meters"
)

path.write_text(
    text,
    encoding="utf-8"
)


# ============================================================
# SoftwareRenderer
# ============================================================

path = root / "src/render/software_renderer.cpp"

text = ensure_include(path)

text = insert_function_timer(
    text,
    "void SoftwareRenderer::draw(",
    "software_3d",
    "SoftwareRenderer::draw"
)

text = insert_function_timer(
    text,
    "void SoftwareRenderer::draw_cockpit_hud(",
    "software_3d",
    "SoftwareRenderer::draw_cockpit_hud"
)

path.write_text(
    text,
    encoding="utf-8"
)


# ============================================================
# Runtime frame boundaries
# ============================================================

path = root / "src/app/starfox_pc.cpp"

text = ensure_include(path)


# ------------------------------------------------------------
# begin_frame
# ------------------------------------------------------------

old = '''        live_fps.reset(raster_timestamp, game.presentation_fps());
        while (running) {
            bool toggle_frame_freeze{};
'''

new = '''        live_fps.reset(raster_timestamp, game.presentation_fps());
        while (running) {
            starfox::app::perf::begin_frame();

            bool toggle_frame_freeze{};
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "Loop principal não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   begin_frame"
    )

else:
    print(
        "JA OK   begin_frame"
    )


# ------------------------------------------------------------
# present + history + end_frame
# ------------------------------------------------------------

old = '''            window.present(
                framebuffer, palette, circle, presentation_effects);
            presentation_history.record(
                framebuffer.width(), framebuffer.height(), window.rgba());
'''

new = '''            {
                starfox::app::perf::ScopedTimer
                    perf_timer_present{
                        starfox::app::perf::Bucket::present};

                window.present(
                    framebuffer,
                    palette,
                    circle,
                    presentation_effects);
            }

            {
                starfox::app::perf::ScopedTimer
                    perf_timer_history{
                        starfox::app::perf::Bucket::history};

                presentation_history.record(
                    framebuffer.width(),
                    framebuffer.height(),
                    window.rgba());
            }

            starfox::app::perf::end_frame();
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "window.present/presentation_history "
            "não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   present/history/end_frame"
    )

else:
    print(
        "JA OK   present/history/end_frame"
    )


path.write_text(
    text,
    encoding="utf-8"
)


# ============================================================
# Switch CMake
# ============================================================

path = root / "ports/switch/CMakeLists.txt"

text = path.read_text(
    encoding="utf-8"
)

marker = "STARFOX_PERF_PROFILER=1"

if marker not in text:

    anchor = '''target_link_libraries(starfox_switch PRIVATE starfox_core SDL3::SDL3)
'''

    if anchor not in text:
        raise RuntimeError(
            "target_link_libraries(starfox_switch) "
            "não encontrado"
        )

    replacement = '''target_link_libraries(starfox_switch PRIVATE starfox_core SDL3::SDL3)

# Temporary Switch performance profiler. Keep the same profiler
# configuration in the core and application translation units so
# the shared inline counters form one process-wide data set.
target_compile_definitions(
    starfox_core
    PRIVATE
        STARFOX_PERF_PROFILER=1
        STARFOX_PERF_SWITCH=1)

target_compile_definitions(
    starfox_switch
    PRIVATE
        STARFOX_PERF_PROFILER=1
        STARFOX_PERF_SWITCH=1)
'''

    text = text.replace(
        anchor,
        replacement,
        1
    )

    print(
        "PATCH   Switch profiler definitions"
    )

else:
    print(
        "JA OK   Switch profiler definitions"
    )

path.write_text(
    text,
    encoding="utf-8"
)

print()
print(
    "Performance profiler instalado."
)
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

echo
echo "Instrumentação:"
grep -R \
    -n \
    'perf_timer_\|begin_frame\|end_frame\|STARFOX_PERF_PROFILER' \
    include/starfox/app/perf_profiler.hpp \
    src/render/background_renderer.cpp \
    src/render/sprite_renderer.cpp \
    src/render/software_renderer.cpp \
    src/app/starfox_pc.cpp \
    ports/switch/CMakeLists.txt \
    | head -n 160

echo
echo
echo "Diff:"
git diff --stat

echo
echo "============================================================"
echo "BUILD + TESTES DESKTOP"
echo "============================================================"

cmake \
    -S . \
    -B "$BUILD_DESKTOP" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_BUILD_SWITCH=OFF

cmake \
    --build "$BUILD_DESKTOP" \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-desktop.log"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest.log"

echo
echo "============================================================"
echo "BUILD NINTENDO SWITCH"
echo "============================================================"

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

"$DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake" \
    -S . \
    -B "$BUILD_SWITCH" \
    -DSTARFOX_BUILD_RUNTIME=OFF \
    -DSTARFOX_BUILD_TESTS=OFF \
    -DSTARFOX_BUILD_SWITCH=ON \
    -DCMAKE_BUILD_TYPE=Release

cmake \
    --build "$BUILD_SWITCH" \
    --target starfox_switch_nro \
    -j"$(nproc)" \
    --verbose \
    2>&1 \
    | tee "$REPORT_DIR/build-switch.log"

NRO="$BUILD_SWITCH/ports/switch/starfox_switch.nro"

echo
echo "============================================================"
echo "VALIDAÇÃO NRO"
echo "============================================================"

test -s "$NRO"

ls -lh "$NRO"

grep -aob \
    'NRO0\|ASET' \
    "$NRO"

sha256sum \
    "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"

echo
echo "============================================================"
echo "PASS 03 CONCLUÍDA"
echo "============================================================"

echo
echo "NRO:"
echo "  $NRO"
echo
echo "Ao executar no Ryujinx, procure linhas:"
echo
echo "  [SFE PERF]"
echo
echo "Exemplo:"
echo
echo "  [SFE PERF] fps=32.10 total=31.15ms bg=... obj=... 3d=..."
echo
echo "IMPORTANTE:"
echo "  ainda NÃO foi criado commit."
echo
echo "Depois do teste, copie cerca de 10-20 linhas [SFE PERF]."

{
    echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 03"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Instrumented buckets:"
    echo "  BG"
    echo "  OBJ"
    echo "  SOFTWARE_3D"
    echo "  PRESENT"
    echo "  HISTORY"
    echo "  OTHER"
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
