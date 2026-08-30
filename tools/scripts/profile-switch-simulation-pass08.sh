#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf08-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-simulation-pass08/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 08"
echo "DETAILED SIMULATION PROFILER"
echo "============================================================"
echo

FILES=(
    include/starfox/app/perf_profiler.hpp
    src/simulation/game_simulation.cpp
    src/simulation/strategy_scheduler.cpp
    src/simulation/map_vm.cpp
    src/simulation/dust_system.cpp
    src/simulation/particle_system.cpp
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
# PROFILER V4
#
# Os buckets finais são divididos em:
#
# PRIMARY
#   entram no cálculo de TOTAL/MISC
#
# DIAGNOSTIC
#   ficam dentro de SIM e NÃO são somados novamente
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

    // ========================================================
    // PRIMARY FRAME BUCKETS
    // ========================================================

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

    // ========================================================
    // SIMULATION DIAGNOSTIC BUCKETS
    //
    // These overlap simulation intentionally.
    // Do not include them in misc/frame accounting.
    // ========================================================

    sim_video,
    sim_native,
    sim_strategies,
    sim_view,
    sim_dust_tick,
    sim_particle_tick,

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


    for (std::size_t i = 0U;
         i < bucket_count;
         ++i) {

        accumulated_time_ns[i] +=
            frame_time_ns[i];

        accumulated_calls[i] +=
            frame_calls[i];
    }


    constexpr std::uint64_t report_frames =
        60U;


    if (accumulated_frames
        < report_frames) {

        return;
    }


    const auto frames =
        static_cast<double>(
            accumulated_frames);


    const auto index =
        [](Bucket bucket) {

            return static_cast<
                std::size_t>(
                    bucket);
        };


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


    const auto per_call =
        [](
            std::uint64_t ns,
            std::uint64_t calls) {

            if (calls == 0U) {
                return 0.0;
            }

            return milliseconds(ns)
                / static_cast<double>(
                    calls);
        };


    // ========================================================
    // PRIMARY BUCKET ACCOUNTING
    //
    // Diagnostic simulation buckets are deliberately excluded.
    // ========================================================

    constexpr std::array primary{
        Bucket::bg1,
        Bucket::bg2,
        Bucket::bg3,

        Bucket::objects,
        Bucket::software_3d,
        Bucket::composite,

        Bucket::simulation,
        Bucket::presentation_logic,
        Bucket::audio,
        Bucket::input,

        Bucket::dust,
        Bucket::particles,
        Bucket::text,

        Bucket::present,
        Bucket::history,
    };


    std::uint64_t measured{};


    for (const auto bucket :
         primary) {

        measured +=
            accumulated_time_ns[
                index(bucket)];
    }


    const auto misc =
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

        ? 1'000.0
            / total_ms

        : 0.0;


    const auto sim_index =
        index(
            Bucket::simulation);

    const auto audio_index =
        index(
            Bucket::audio);

    const auto native_index =
        index(
            Bucket::sim_native);

    const auto strategy_index =
        index(
            Bucket::sim_strategies);


    char line[2600]{};


    const auto length =
        std::snprintf(
            line,
            sizeof(line),

            "[SFE PERF4] "

            "fps=%.2f "
            "total=%.3fms "

            "bg1=%.3fms "
            "bg2=%.3fms "
            "bg3=%.3fms "

            "comp=%.3fms "
            "obj=%.3fms "
            "3d=%.3fms "

            "sim=%.3fms "
            "simcall=%.3fms "

            "audio=%.3fms "
            "audiocall=%.3fms "

            "native=%.3fms "
            "nativecall=%.3fms "

            "strat=%.3fms "
            "stratcall=%.3fms "

            "view=%.3fms "
            "video=%.3fms "
            "dusttick=%.3fms "
            "parttick=%.3fms "

            "input=%.3fms "
            "text=%.3fms "

            "present=%.3fms "
            "history=%.3fms "
            "misc=%.3fms "

            "calls(sim/audio/native/strat)="
            "%.2f/%.2f/%.2f/%.2f\n",

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
                    sim_index]),

            per_call(
                accumulated_time_ns[
                    sim_index],
                accumulated_calls[
                    sim_index]),

            average(
                accumulated_time_ns[
                    audio_index]),

            per_call(
                accumulated_time_ns[
                    audio_index],
                accumulated_calls[
                    audio_index]),

            average(
                accumulated_time_ns[
                    native_index]),

            per_call(
                accumulated_time_ns[
                    native_index],
                accumulated_calls[
                    native_index]),

            average(
                accumulated_time_ns[
                    strategy_index]),

            per_call(
                accumulated_time_ns[
                    strategy_index],
                accumulated_calls[
                    strategy_index]),

            average(
                accumulated_time_ns[
                    index(Bucket::sim_view)]),

            average(
                accumulated_time_ns[
                    index(Bucket::sim_video)]),

            average(
                accumulated_time_ns[
                    index(Bucket::sim_dust_tick)]),

            average(
                accumulated_time_ns[
                    index(Bucket::sim_particle_tick)]),

            average(
                accumulated_time_ns[
                    index(Bucket::input)]),

            average(
                accumulated_time_ns[
                    index(Bucket::text)]),

            average(
                accumulated_time_ns[
                    index(Bucket::present)]),

            average(
                accumulated_time_ns[
                    index(Bucket::history)]),

            average(
                misc),

            average_calls(
                accumulated_calls[
                    sim_index]),

            average_calls(
                accumulated_calls[
                    audio_index]),

            average_calls(
                accumulated_calls[
                    native_index]),

            average_calls(
                accumulated_calls[
                    strategy_index]));


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
            f"Nenhum include encontrado em {path}"
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

    text = ensure_include(
        path
    )

    start = text.find(
        function_token
    )

    if start < 0:
        raise RuntimeError(
            f"Função não encontrada: "
            f"{function_token} "
            f"em {path}"
        )

    search_end = min(
        len(text),
        start + 1800
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
# GAME SIMULATION
# ============================================================

game = (
    root
    / "src/simulation/game_simulation.cpp"
)


instrument(
    game,
    "GameSimulation::complete_video_phases_for_tick(",
    "sim_video",
    "perf_timer_sim_video"
)


instrument(
    game,
    "GameSimulation::update_view_flags_and_cull(",
    "sim_view",
    "perf_timer_sim_view"
)


# ============================================================
# STRATEGY SCHEDULER
# ============================================================

strategies = (
    root
    / "src/simulation/strategy_scheduler.cpp"
)


instrument(
    strategies,
    "NativeStrategyScheduler::begin_tick(",
    "sim_strategies",
    "perf_timer_strategy_begin"
)


instrument(
    strategies,
    "NativeStrategyScheduler::tick_all(",
    "sim_strategies",
    "perf_timer_strategy_all"
)


instrument(
    strategies,
    "NativeStrategyScheduler::tick_all_no_objects(",
    "sim_strategies",
    "perf_timer_strategy_no_objects"
)


# ============================================================
# MAP VM / NATIVE 65816 EXECUTION
# ============================================================

map_vm = (
    root
    / "src/simulation/map_vm.cpp"
)


instrument(
    map_vm,
    "MapVm::call_native_routine(",
    "sim_native",
    "perf_timer_native_routine"
)


instrument(
    map_vm,
    "MapVm::call_native_object_routine(",
    "sim_native",
    "perf_timer_native_object"
)


instrument(
    map_vm,
    "MapVm::resume_native_task(",
    "sim_native",
    "perf_timer_native_task"
)


# ============================================================
# HOST DUST TICK
# ============================================================

dust = (
    root
    / "src/simulation/dust_system.cpp"
)


instrument(
    dust,
    "DustSystem::tick(",
    "sim_dust_tick",
    "perf_timer_sim_dust"
)


# ============================================================
# HOST PARTICLE TICK
# ============================================================

particles = (
    root
    / "src/simulation/particle_system.cpp"
)


instrument(
    particles,
    "ParticleSystem::tick(",
    "sim_particle_tick",
    "perf_timer_sim_particles"
)


print()
print(
    "Performance Pass 08 instrumentation installed."
)
PY


echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check


echo
echo "Timers de simulação:"
grep -R \
    -n \
    'perf_timer_sim_video\|perf_timer_sim_view\|perf_timer_strategy_\|perf_timer_native_\|perf_timer_sim_dust\|perf_timer_sim_particles' \
    src/simulation \
    | head -n 200


echo
echo
echo "Profiler V4:"
grep -n \
    'sim_native\|sim_strategies\|sim_view\|sim_video\|sim_dust_tick\|sim_particle_tick\|simcall\|audiocall' \
    include/starfox/app/perf_profiler.hpp \
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
echo "PASS 08 CONCLUÍDA"
echo "============================================================"

echo
echo "Profiler:"
echo "  [SFE PERF4]"
echo
echo "Novos dados:"
echo "  simcall    = custo por logic tick"
echo "  audiocall  = custo por SPC tick"
echo "  native     = execução 65C816"
echo "  strat      = strategy scheduler"
echo "  view       = view/culling"
echo "  video      = video phases"
echo "  dusttick   = lógica dust"
echo "  parttick   = lógica particles"
echo
echo "IMPORTANTE:"
echo "  buckets internos se sobrepõem a SIM."
echo "  eles NÃO são somados novamente ao TOTAL."
echo
echo "NRO:"
echo "  $NRO"
echo
echo "Ainda NÃO foi criado commit."
echo "Teste novamente SEM gravação."
echo
echo "Git status:"
git status --short


{
    echo "STAR FOX ENHANCED — PERFORMANCE PASS 08"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Profiler:"
    echo "  [SFE PERF4]"
    echo
    echo "Diagnostic simulation buckets:"
    echo "  simcall"
    echo "  audiocall"
    echo "  native"
    echo "  strategies"
    echo "  view/culling"
    echo "  video phases"
    echo "  dust tick"
    echo "  particle tick"
} > "$REPORT_DIR/report-share.txt"


echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
