#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf04-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass04/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 04"
echo "BG PROFILING + FAST LAYER COMPOSITOR"
echo "============================================================"
echo

FILES=(
    include/starfox/app/perf_profiler.hpp
    include/starfox/render/framebuffer.hpp
    src/render/background_renderer.cpp
    src/render/framebuffer.cpp
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

# ============================================================
# PROFILER V2
# ============================================================

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
    bg1,
    bg2,
    bg3,

    objects,
    software_3d,
    composite,
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

inline std::array<
    std::uint64_t,
    bucket_count>
    frame_time_ns{};

inline std::array<
    std::uint64_t,
    bucket_count>
    frame_calls{};

inline std::array<
    std::uint64_t,
    bucket_count>
    accumulated_time_ns{};

inline std::array<
    std::uint64_t,
    bucket_count>
    accumulated_calls{};

inline Clock::time_point frame_begin{};

inline std::uint64_t
    accumulated_total_ns{};

inline std::uint64_t
    accumulated_frames{};

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

        const auto elapsed =
            std::chrono::duration_cast<
                Nanoseconds>(
                    Clock::now()
                    - begin_);

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

    return static_cast<double>(
        ns)
        / 1'000'000.0;
}

inline void end_frame() noexcept {

    if (!enabled()) {
        return;
    }

    const auto total =
        static_cast<std::uint64_t>(
            std::chrono::duration_cast<
                Nanoseconds>(
                    Clock::now()
                    - frame_begin)
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

    constexpr std::uint64_t
        report_frames = 60U;

    if (accumulated_frames
        < report_frames) {

        return;
    }

    const auto frames =
        static_cast<double>(
            accumulated_frames);

    const auto average =
        [frames](
            std::uint64_t ns) {

            return milliseconds(ns)
                / frames;
        };

    const auto average_calls =
        [frames](
            std::uint64_t calls) {

            return static_cast<double>(
                calls)
                / frames;
        };

    const auto index =
        [](Bucket bucket) {

            return static_cast<
                std::size_t>(
                    bucket);
        };

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

    const auto fps =
        total_ms > 0.0
        ? 1'000.0 / total_ms
        : 0.0;

    char line[1400]{};

    const auto length =
        std::snprintf(
            line,
            sizeof(line),

            "[SFE PERF2] "
            "fps=%.2f "
            "total=%.3fms "
            "bg1=%.3fms "
            "bg2=%.3fms "
            "bg3=%.3fms "
            "comp=%.3fms "
            "obj=%.3fms "
            "3d=%.3fms "
            "present=%.3fms "
            "history=%.3fms "
            "other=%.3fms "
            "calls(bg1/bg2/bg3/comp)="
            "%.1f/%.1f/%.1f/%.1f\n",

            fps,
            total_ms,

            average(
                accumulated_time_ns[
                    index(Bucket::bg1)]),

            average(
                accumulated_time_ns[
                    index(Bucket::bg2)]),

            average(
                accumulated_time_ns[
                    index(Bucket::bg3)]),

            average(
                accumulated_time_ns[
                    index(Bucket::composite)]),

            average(
                accumulated_time_ns[
                    index(Bucket::objects)]),

            average(
                accumulated_time_ns[
                    index(Bucket::software_3d)]),

            average(
                accumulated_time_ns[
                    index(Bucket::present)]),

            average(
                accumulated_time_ns[
                    index(Bucket::history)]),

            average(other),

            average_calls(
                accumulated_calls[
                    index(Bucket::bg1)]),

            average_calls(
                accumulated_calls[
                    index(Bucket::bg2)]),

            average_calls(
                accumulated_calls[
                    index(Bucket::bg3)]),

            average_calls(
                accumulated_calls[
                    index(Bucket::composite)]));

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
import re

root = Path(
    os.environ["PROJECT_ROOT"])


# ============================================================
# BACKGROUND PROFILER:
#
# antigo:
#
#   Bucket::background
#
# novo:
#
#   draw_bg1 -> Bucket::bg1
#   draw_bg2 -> Bucket::bg2
#   draw_bg3 -> Bucket::bg3
# ============================================================

path = root / "src/render/background_renderer.cpp"

text = path.read_text(
    encoding="utf-8")


def patch_bucket(
    source,
    function,
    bucket):

    start = source.find(function)

    if start < 0:
        raise RuntimeError(
            f"{function} não encontrado")

    next_start = source.find(
            "\nvoid BackgroundRenderer::",
            start + len(function))

    if next_start < 0:
        next_start = source.find(
                "\n} // namespace starfox::render",
                start)

    if next_start < 0:
        next_start = len(source)

    section = source[start:next_start]

    if (
        f"Bucket::{bucket}"
        in section
    ):
        print(
            f"JA OK   {function} -> {bucket}")

        return source

    section_new = re.sub(
        r'Bucket::background',
        f'Bucket::{bucket}',
        section,
        count=1)

    if section_new == section:
        raise RuntimeError(
            f"Timer antigo não encontrado em "
            f"{function}")

    print(
        f"PATCH   {function} -> {bucket}")

    return (
        source[:start]
        + section_new
        + source[next_start:]
    )


text = patch_bucket(
    text,
    "void BackgroundRenderer::draw_bg1(",
    "bg1")

text = patch_bucket(
    text,
    "void BackgroundRenderer::draw_bg2(",
    "bg2")

text = patch_bucket(
    text,
    "void BackgroundRenderer::draw_bg3(",
    "bg3")

path.write_text(
    text,
    encoding="utf-8")


# ============================================================
# FRAMEBUFFER COMPOSITOR
# ============================================================

path = root / "src/render/framebuffer.cpp"

text = path.read_text(
    encoding="utf-8")


profiler_include = (
    '#include "starfox/app/perf_profiler.hpp"\n'
)

if profiler_include not in text:

    anchor = (
        '#include "starfox/render/framebuffer.hpp"\n'
    )

    if anchor not in text:
        raise RuntimeError(
            "include framebuffer não encontrado")

    text = text.replace(
        anchor,
        anchor + profiler_include,
        1)

    print(
        "PATCH   framebuffer profiler include")


begin = text.find(
    "void composite_transparent_layer(")

end = text.find(
    "\nvoid write_bmp(",
    begin)

if begin < 0 or end < 0:
    raise RuntimeError(
        "composite_transparent_layer não encontrado")


new_function = r'''void composite_transparent_layer(
    const Framebuffer& source,
    Framebuffer& destination,
    const LayerCompositeSettings& settings) noexcept {

    starfox::app::perf::ScopedTimer
        perf_timer_composite{
            starfox::app::perf::Bucket::composite};

    const auto source_width =
        static_cast<std::int32_t>(
            source.width());

    const auto source_height =
        static_cast<std::int32_t>(
            source.height());

    const auto destination_width =
        static_cast<std::int32_t>(
            destination.width());

    const auto destination_height =
        static_cast<std::int32_t>(
            destination.height());

    const auto mosaic_enabled =
        settings.mosaic_layer_mask != 0U
        && (settings.mosaic
            & settings.mosaic_layer_mask)
            != 0U;

    // ========================================================
    // COMMON FAST PATH
    //
    // Most gameplay layers have mosaic disabled.
    //
    // The old implementation scanned the complete source and,
    // for every pixel:
    //
    //   - recalculated destination_x/y
    //   - checked four clip comparisons
    //   - called source.get()
    //   - called destination.set()
    //
    // Clip the rectangle once, acquire row pointers once per
    // scanline, and copy only non-transparent source pixels.
    // ========================================================

    if (!mosaic_enabled) {

        const auto destination_left =
            std::max({
                0,
                settings.clip_left,
                settings.offset_x});

        const auto destination_top =
            std::max({
                0,
                settings.clip_top,
                settings.offset_y});

        const auto destination_right =
            std::min({
                destination_width,
                settings.clip_right,
                settings.offset_x
                    + source_width});

        const auto destination_bottom =
            std::min({
                destination_height,
                settings.clip_bottom,
                settings.offset_y
                    + source_height});

        if (destination_left
                >= destination_right
            || destination_top
                >= destination_bottom) {

            return;
        }

        const auto source_left =
            destination_left
            - settings.offset_x;

        const auto copy_width =
            destination_right
            - destination_left;

        for (auto destination_y =
                 destination_top;
             destination_y
                 < destination_bottom;
             ++destination_y) {

            const auto source_y =
                destination_y
                - settings.offset_y;

            const auto* source_row =
                source.row_data(
                    static_cast<
                        std::uint32_t>(
                            source_y));

            auto* destination_row =
                destination.row_data(
                    static_cast<
                        std::uint32_t>(
                            destination_y));

            const auto* src =
                source_row
                + source_left;

            auto* dst =
                destination_row
                + destination_left;

            for (auto column = 0;
                 column < copy_width;
                 ++column) {

                const auto colour =
                    src[column];

                if (colour != 0U) {
                    dst[column] =
                        colour;
                }
            }
        }

        return;
    }

    // ========================================================
    // MOSAIC PATH
    //
    // Mosaic requires sampling a different source coordinate,
    // but clipping and destination row access can still be
    // moved outside the inner pixel work.
    // ========================================================

    const auto mosaic_size =
        static_cast<std::int32_t>(
            (settings.mosaic >> 4U)
            + 1U);

    const auto destination_left =
        std::max(
            0,
            settings.clip_left);

    const auto destination_top =
        std::max(
            0,
            settings.clip_top);

    const auto destination_right =
        std::min(
            destination_width,
            settings.clip_right);

    const auto destination_bottom =
        std::min(
            destination_height,
            settings.clip_bottom);

    if (destination_left
            >= destination_right
        || destination_top
            >= destination_bottom) {

        return;
    }

    for (auto destination_y =
             destination_top;
         destination_y
             < destination_bottom;
         ++destination_y) {

        const auto logical_y =
            destination_y
            - settings.mosaic_origin_y;

        const auto sampled_logical_y =
            mosaic_coordinate(
                logical_y,
                mosaic_size);

        const auto source_y =
            sampled_logical_y
            + settings.mosaic_origin_y
            - settings.offset_y;

        if (source_y < 0
            || source_y >= source_height) {

            continue;
        }

        const auto* source_row =
            source.row_data(
                static_cast<
                    std::uint32_t>(
                        source_y));

        auto* destination_row =
            destination.row_data(
                static_cast<
                    std::uint32_t>(
                        destination_y));

        for (auto destination_x =
                 destination_left;
             destination_x
                 < destination_right;
             ++destination_x) {

            const auto logical_x =
                destination_x
                - settings.mosaic_origin_x;

            const auto sampled_logical_x =
                mosaic_coordinate(
                    logical_x,
                    mosaic_size);

            const auto source_x =
                sampled_logical_x
                + settings.mosaic_origin_x
                - settings.offset_x;

            if (source_x < 0
                || source_x >= source_width) {

                continue;
            }

            const auto colour =
                source_row[source_x];

            if (colour != 0U) {

                destination_row[
                    destination_x] =
                    colour;
            }
        }
    }
}
'''

text = (
    text[:begin]
    + new_function
    + text[end:]
)

path.write_text(
    text,
    encoding="utf-8")

print(
    "PATCH   optimized composite_transparent_layer")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

echo
echo "Profiler buckets:"
grep -R \
    -n \
    'Bucket::bg1\|Bucket::bg2\|Bucket::bg3\|Bucket::composite' \
    src/render \
    | head -n 80

echo
echo
echo "Compositor:"
grep -n \
    -A40 \
    'void composite_transparent_layer' \
    src/render/framebuffer.cpp \
    | head -n 80

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
echo "PASS 04 CONCLUÍDA"
echo "============================================================"

echo
echo "Novo NRO:"
echo "  $NRO"
echo
echo "Ao executar no Ryujinx procure:"
echo
echo "  [SFE PERF2]"
echo
echo "Agora teremos:"
echo
echo "  bg1"
echo "  bg2"
echo "  bg3"
echo "  comp"
echo "  obj"
echo "  3d"
echo "  present"
echo "  history"
echo "  other"
echo
echo "IMPORTANTE:"
echo "  ainda NÃO foi criado commit."
echo
echo "Git status:"
git status --short

{
    echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 04"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Changes:"
    echo "  BG1/BG2/BG3 separate profiling"
    echo "  Composite-layer profiling"
    echo "  Fast non-mosaic scanline compositor"
    echo "  Direct framebuffer row access"
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
