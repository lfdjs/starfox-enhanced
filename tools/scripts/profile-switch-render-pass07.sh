#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf07-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass07/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 07"
echo "DETAILED OTHER-BUCKET PROFILER"
echo "============================================================"
echo

FILES=(
    include/starfox/app/perf_profiler.hpp
    src/simulation/game_simulation.cpp
    src/audio/spc700_audio.cpp
    src/app/runtime_input.cpp
    src/render/dust_renderer.cpp
    src/render/particle_renderer.cpp
    src/render/scaled_text_renderer.cpp
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
# PROFILER V3
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

    simulation,
    presentation_logic,
    audio,
    input,

    dust,
    particles,
    text,

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

    return static_cast<double>(ns)
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


    const auto calls =
        [frames](
            std::uint64_t value) {

            return static_cast<double>(
                value)
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
        accumulated_total_ns > measured
        ? accumulated_total_ns - measured
        : 0U;


    const auto total_ms =
        average(
            accumulated_total_ns);


    const auto fps =
        total_ms > 0.0
        ? 1'000.0 / total_ms
        : 0.0;


    char line[2048]{};


    const auto length =
        std::snprintf(
            line,
            sizeof(line),

            "[SFE PERF3] "
            "fps=%.2f "
            "total=%.3fms "

            "bg1=%.3fms "
            "bg2=%.3fms "
            "bg3=%.3fms "

            "comp=%.3fms "
            "obj=%.3fms "
            "3d=%.3fms "

            "sim=%.3fms "
            "flog=%.3fms "
            "audio=%.3fms "
            "input=%.3fms "

            "dust=%.3fms "
            "part=%.3fms "
            "text=%.3fms "

            "present=%.3fms "
            "history=%.3fms "
            "misc=%.3fms "

            "calls(sim/audio/dust/part/text)="
            "%.2f/%.2f/%.2f/%.2f/%.2f\n",

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
                    index(Bucket::simulation)]),

            average(
                accumulated_time_ns[
                    index(Bucket::presentation_logic)]),

            average(
                accumulated_time_ns[
                    index(Bucket::audio)]),

            average(
                accumulated_time_ns[
                    index(Bucket::input)]),

            average(
                accumulated_time_ns[
                    index(Bucket::dust)]),

            average(
                accumulated_time_ns[
                    index(Bucket::particles)]),

            average(
                accumulated_time_ns[
                    index(Bucket::text)]),

            average(
                accumulated_time_ns[
                    index(Bucket::present)]),

            average(
                accumulated_time_ns[
                    index(Bucket::history)]),

            average(other),

            calls(
                accumulated_calls[
                    index(Bucket::simulation)]),

            calls(
                accumulated_calls[
                    index(Bucket::audio)]),

            calls(
                accumulated_calls[
                    index(Bucket::dust)]),

            calls(
                accumulated_calls[
                    index(Bucket::particles)]),

            calls(
                accumulated_calls[
                    index(Bucket::text)]));


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

root = Path(
    os.environ["PROJECT_ROOT"]
)

profiler_include = (
    '#include "starfox/app/perf_profiler.hpp"\n'
)


def ensure_include(path):
    text = path.read_text(
        encoding="utf-8"
    )

    if profiler_include in text:
        return text

    first_include = text.find(
        "#include "
    )

    if first_include < 0:
        raise RuntimeError(
            f"Não encontrei include em {path}"
        )

    text = (
        text[:first_include]
        + profiler_include
        + text[first_include:]
    )

    return text


def instrument(
    path,
    function_token,
    bucket,
    marker):

    text = ensure_include(path)

    start = text.find(
        function_token
    )

    if start < 0:
        raise RuntimeError(
            f"Função não encontrada: "
            f"{function_token} em {path}"
        )

    # Avoid duplicating the timer if Pass 07 is rerun.
    search_end = min(
        len(text),
        start + 1400
    )

    if marker in text[
        start:search_end
    ]:

        print(
            f"JA OK   {function_token}"
        )

        path.write_text(
            text,
            encoding="utf-8"
        )

        return


    brace = text.find(
        "{",
        start
    )

    if brace < 0:
        raise RuntimeError(
            f"Corpo não encontrado: "
            f"{function_token}"
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


    path.write_text(
        text,
        encoding="utf-8"
    )

    print(
        f"PATCH   {function_token}"
        f" -> {bucket}"
    )


# ============================================================
# SIMULATION
# ============================================================

game = (
    root
    / "src/simulation/game_simulation.cpp"
)

instrument(
    game,
    "GameSimulation::tick(",
    "simulation",
    "perf_timer_simulation"
)

instrument(
    game,
    "GameSimulation::present_frame(",
    "presentation_logic",
    "perf_timer_presentation_logic"
)


# ============================================================
# SPC700 / AUDIO
# ============================================================

audio = (
    root
    / "src/audio/spc700_audio.cpp"
)

instrument(
    audio,
    "Spc700Audio::render_logic_tick(",
    "audio",
    "perf_timer_audio"
)


# ============================================================
# INPUT
# ============================================================

runtime_input = (
    root
    / "src/app/runtime_input.cpp"
)

instrument(
    runtime_input,
    "InputBindings::sample(",
    "input",
    "perf_timer_input_sample"
)

instrument(
    runtime_input,
    "InputBindings::sample_gamepad_only(",
    "input",
    "perf_timer_input_gamepad"
)

instrument(
    runtime_input,
    "InputBindings::sample_fixed_menu_navigation(",
    "input",
    "perf_timer_input_menu"
)


# ============================================================
# DUST / GRID
# ============================================================

dust = (
    root
    / "src/render/dust_renderer.cpp"
)

instrument(
    dust,
    "DustRenderer::draw(",
    "dust",
    "perf_timer_dust_draw"
)

instrument(
    dust,
    "DustRenderer::draw_grid(",
    "dust",
    "perf_timer_dust_grid"
)

instrument(
    dust,
    "DustRenderer::draw_grid_lines(",
    "dust",
    "perf_timer_dust_grid_lines"
)


# ============================================================
# PARTICLES
# ============================================================

particles = (
    root
    / "src/render/particle_renderer.cpp"
)

instrument(
    particles,
    "ParticleRenderer::draw_owner(",
    "particles",
    "perf_timer_particles"
)


# ============================================================
# TEXT / FACES / HOST HUD
# ============================================================

text_renderer = (
    root
    / "src/render/scaled_text_renderer.cpp"
)

functions = [
    (
        "ScaledTextRenderer::draw(",
        "perf_timer_text_draw"
    ),
    (
        "ScaledTextRenderer::draw_game_text(",
        "perf_timer_text_game"
    ),
    (
        "ScaledTextRenderer::draw_face(",
        "perf_timer_text_face"
    ),
    (
        "ScaledTextRenderer::draw_ascii(",
        "perf_timer_text_ascii"
    ),
    (
        "ScaledTextRenderer::draw_utf8(",
        "perf_timer_text_utf8"
    ),
    (
        "ScaledTextRenderer::draw_utf8_wrapped(",
        "perf_timer_text_wrapped"
    ),
]

for function_token, marker in functions:

    instrument(
        text_renderer,
        function_token,
        "text",
        marker
    )


print()
print(
    "Performance Pass 07 instrumentation installed."
)
PY


echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check


echo
echo "Timers instalados:"
grep -R \
    -n \
    'perf_timer_simulation\|perf_timer_audio\|perf_timer_input\|perf_timer_dust\|perf_timer_particles\|perf_timer_text\|perf_timer_presentation_logic' \
    src/simulation/game_simulation.cpp \
    src/audio/spc700_audio.cpp \
    src/app/runtime_input.cpp \
    src/render/dust_renderer.cpp \
    src/render/particle_renderer.cpp \
    src/render/scaled_text_renderer.cpp \
    | head -n 200


echo
echo
echo "Buckets PERF3:"
grep -n \
    'simulation\|presentation_logic\|audio\|input\|dust\|particles\|text' \
    include/starfox/app/perf_profiler.hpp \
    | head -n 120


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
echo "BUILD SWITCH"
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
echo "PASS 07 CONCLUÍDA"
echo "============================================================"

echo
echo "Novo profiler:"
echo "  [SFE PERF3]"
echo
echo "Campos adicionais:"
echo "  sim    = GameSimulation::tick"
echo "  flog   = GameSimulation::present_frame"
echo "  audio  = SPC700 render_logic_tick"
echo "  input  = input sampling"
echo "  dust   = dust/grid"
echo "  part   = particles"
echo "  text   = text/faces"
echo "  misc   = residual ainda não classificado"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "IMPORTANTE:"
echo "  NÃO foi criado commit."
echo "  NÃO grave vídeo durante o teste."
echo
echo "Git status:"
git status --short


{
    echo "STAR FOX ENHANCED — PERFORMANCE PASS 07"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Profiler:"
    echo "  [SFE PERF3]"
    echo
    echo "Buckets:"
    echo "  simulation"
    echo "  presentation_logic"
    echo "  audio"
    echo "  input"
    echo "  dust"
    echo "  particles"
    echo "  text"
    echo "  misc residual"
} > "$REPORT_DIR/report-share.txt"


echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
