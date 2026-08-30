#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf09-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-native-sync-pass09/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 09"
echo "NATIVE CPU / OBJECT SYNC PROFILER"
echo "============================================================"
echo

FILES=(
    include/starfox/app/perf_profiler.hpp
    src/simulation/map_vm.cpp
    src/simulation/wdc65816.cpp
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
# PROFILER V5
#
# Primary buckets:
#   enter TOTAL/MISC accounting.
#
# Diagnostic buckets:
#   overlap SIM/NATIVE and therefore MUST NOT be added to
#   TOTAL again.
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

    // Primary frame buckets
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

    // Simulation diagnostics
    sim_video,
    sim_native,
    sim_strategies,
    sim_view,
    sim_dust_tick,
    sim_particle_tick,

    // Native-execution diagnostics
    sim_sync_to_cpu,
    sim_sync_from_cpu,
    sim_cpu_core,

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


    // Only these buckets contribute independently to frame total.
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
        accumulated_total_ns > measured

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


    const auto sim_i =
        index(
            Bucket::simulation);

    const auto audio_i =
        index(
            Bucket::audio);

    const auto native_i =
        index(
            Bucket::sim_native);

    const auto strat_i =
        index(
            Bucket::sim_strategies);

    const auto sync_to_i =
        index(
            Bucket::sim_sync_to_cpu);

    const auto sync_from_i =
        index(
            Bucket::sim_sync_from_cpu);

    const auto cpu_i =
        index(
            Bucket::sim_cpu_core);


    char line[3000]{};


    const auto length =
        std::snprintf(
            line,
            sizeof(line),

            "[SFE PERF5] "

            "fps=%.2f "
            "total=%.3fms "

            "bg1=%.3fms "
            "bg2=%.3fms "
            "bg3=%.3fms "

            "comp=%.3fms "
            "3d=%.3fms "

            "sim=%.3fms "
            "simcall=%.3fms "

            "audio=%.3fms "
            "audiocall=%.3fms "

            "native=%.3fms "
            "nativecall=%.3fms "

            "strat=%.3fms "
            "stratcall=%.3fms "

            "sync_to=%.3fms "
            "sync_to_call=%.3fms "

            "sync_from=%.3fms "
            "sync_from_call=%.3fms "

            "cpu=%.3fms "
            "cpu_call=%.3fms "

            "view=%.3fms "
            "video=%.3fms "

            "present=%.3fms "
            "misc=%.3fms "

            "calls(sim/native/sync_to/sync_from/cpu)="
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
                    index(Bucket::software_3d)]),

            average(
                accumulated_time_ns[
                    sim_i]),

            per_call(
                accumulated_time_ns[
                    sim_i],
                accumulated_calls[
                    sim_i]),

            average(
                accumulated_time_ns[
                    audio_i]),

            per_call(
                accumulated_time_ns[
                    audio_i],
                accumulated_calls[
                    audio_i]),

            average(
                accumulated_time_ns[
                    native_i]),

            per_call(
                accumulated_time_ns[
                    native_i],
                accumulated_calls[
                    native_i]),

            average(
                accumulated_time_ns[
                    strat_i]),

            per_call(
                accumulated_time_ns[
                    strat_i],
                accumulated_calls[
                    strat_i]),

            average(
                accumulated_time_ns[
                    sync_to_i]),

            per_call(
                accumulated_time_ns[
                    sync_to_i],
                accumulated_calls[
                    sync_to_i]),

            average(
                accumulated_time_ns[
                    sync_from_i]),

            per_call(
                accumulated_time_ns[
                    sync_from_i],
                accumulated_calls[
                    sync_from_i]),

            average(
                accumulated_time_ns[
                    cpu_i]),

            per_call(
                accumulated_time_ns[
                    cpu_i],
                accumulated_calls[
                    cpu_i]),

            average(
                accumulated_time_ns[
                    index(Bucket::sim_view)]),

            average(
                accumulated_time_ns[
                    index(Bucket::sim_video)]),

            average(
                accumulated_time_ns[
                    index(Bucket::present)]),

            average(
                misc),

            average_calls(
                accumulated_calls[
                    sim_i]),

            average_calls(
                accumulated_calls[
                    native_i]),

            average_calls(
                accumulated_calls[
                    sync_to_i]),

            average_calls(
                accumulated_calls[
                    sync_from_i]),

            average_calls(
                accumulated_calls[
                    cpu_i]));


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
            f"Include não encontrado em {path}"
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
            f"{function_token} em {path}"
        )

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
# MAP VM OBJECT SYNCHRONIZATION
# ============================================================

map_vm = (
    root
    / "src/simulation/map_vm.cpp"
)


instrument(
    map_vm,
    "void MapVm::sync_objects_to_cpu(",
    "sim_sync_to_cpu",
    "perf_timer_sync_to_cpu"
)


instrument(
    map_vm,
    "void MapVm::sync_objects_from_cpu(",
    "sim_sync_from_cpu",
    "perf_timer_sync_from_cpu"
)


# ============================================================
# RAW 65816 CORE EXECUTION
# ============================================================

wdc = (
    root
    / "src/simulation/wdc65816.cpp"
)


instrument(
    wdc,
    "std::size_t Wdc65816::call(",
    "sim_cpu_core",
    "perf_timer_cpu_call"
)


instrument(
    wdc,
    "Wdc65816TaskResult Wdc65816::run_task(",
    "sim_cpu_core",
    "perf_timer_cpu_task"
)


print()
print(
    "Pass 09 native/sync profiler installed."
)
PY


echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"


git diff --check


echo
echo "SYNC timers:"
grep -R \
    -n \
    'perf_timer_sync_to_cpu\|perf_timer_sync_from_cpu' \
    src/simulation/map_vm.cpp


echo
echo
echo "CPU timers:"
grep -R \
    -n \
    'perf_timer_cpu_call\|perf_timer_cpu_task' \
    src/simulation/wdc65816.cpp


echo
echo
echo "Profiler V5:"
grep -n \
    'sim_sync_to_cpu\|sim_sync_from_cpu\|sim_cpu_core\|SFE PERF5' \
    include/starfox/app/perf_profiler.hpp


echo
echo
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
echo "PASS 09 CONCLUÍDA"
echo "============================================================"

echo
echo "Profiler:"
echo "  [SFE PERF5]"
echo
echo "Novos campos:"
echo "  sync_to       host ObjectPool -> 65C816 WRAM"
echo "  sync_from     65C816 WRAM -> host ObjectPool"
echo "  cpu           execução efetiva do core 65C816"
echo
echo "Todos são diagnósticos internos."
echo "Não entram novamente no cálculo do TOTAL."
echo
echo "NRO:"
echo "  $NRO"
echo
echo "Ainda NÃO foi criado commit."
echo "Teste novamente SEM gravação de vídeo."
echo


{
    echo "STAR FOX ENHANCED — PERFORMANCE PASS 09"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Profiler:"
    echo "  [SFE PERF5]"
    echo
    echo "Native diagnostic:"
    echo "  sync_to_cpu"
    echo "  sync_from_cpu"
    echo "  raw_65816_cpu"
} > "$REPORT_DIR/report-share.txt"


echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"

echo
echo "Git status:"
git status --short
