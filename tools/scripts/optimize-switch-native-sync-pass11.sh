#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf11-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-native-sync-pass11/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 11"
echo "CHANGE-AWARE CPU -> HOST OBJECT SYNCHRONIZATION"
echo "============================================================"
echo

FILES=(
    src/simulation/map_vm.cpp
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

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(
    os.environ["PROJECT_ROOT"]
)

path = (
    root
    / "src/simulation/map_vm.cpp"
)

text = path.read_text(
    encoding="utf-8"
)


# ============================================================
# PRÉ-REQUISITOS
# ============================================================

required = [
    "cpu_.work_ram()",
    "sim_sync_from_cpu",
    "void MapVm::sync_objects_from_cpu()",
]

for token in required:

    if token not in text:

        raise RuntimeError(
            f"Pré-requisito da Pass 10 ausente: {token}"
        )


start = text.find(
    "void MapVm::sync_objects_from_cpu()"
)

end = text.find(
    "\nvoid MapVm::execute_inline_65816()",
    start
)

if start < 0 or end < 0:

    raise RuntimeError(
        "Não foi possível delimitar "
        "sync_objects_from_cpu()"
    )


old_function = text[start:end]


if "PASS11_CHANGE_AWARE_SYNC_FROM" in old_function:

    print(
        "JA OK   Pass 11 já aplicada."
    )

else:

    new_function = r'''void MapVm::sync_objects_from_cpu() {
    // PASS11_CHANGE_AWARE_SYNC_FROM
    //
    // Native routines normally modify only a small subset of the active
    // object pool. The old bridge rebuilt both linked lists and rewrote
    // every semantic byte of every active object after every 65816 call.
    //
    // Preserve identical semantics while avoiding redundant host writes:
    //
    //  1. read the native active/free lists;
    //  2. rebuild ObjectPool links only when those lists actually changed;
    //  3. import only base/extended bytes whose values differ;
    //  4. always keep semantic mirrors derived from the extended block
    //     coherent.
    //
    // CPU -> host synchronization still occurs after every native call.

    starfox::app::perf::ScopedTimer
        perf_timer_sync_from_cpu{
            starfox::app::perf::Bucket::sim_sync_from_cpu};


    const auto work_ram =
        cpu_.work_ram();


    const auto starfox_work_ram_offset =
        [](std::uint32_t address) noexcept
            -> std::size_t {

        const auto bank =
            static_cast<std::uint8_t>(
                address >> 16U);

        if (bank == 0x7eU
            || bank == 0x7fU) {

            return static_cast<std::size_t>(
                address & 0x1ffffU);
        }

        // Banks $00-$3f/$80-$bf mirror the first
        // 8 KiB of SNES WRAM.
        return static_cast<std::size_t>(
            address & 0x1fffU);
    };


    const auto starfox_work_ram_read8 =
        [&work_ram,
         &starfox_work_ram_offset](
            std::uint32_t address) noexcept
            -> std::uint8_t {

        return work_ram[
            starfox_work_ram_offset(
                address)];
    };


    const auto starfox_work_ram_read16 =
        [&starfox_work_ram_read8](
            std::uint32_t address) noexcept
            -> std::uint16_t {

        return static_cast<std::uint16_t>(
            starfox_work_ram_read8(
                address))
            | (
                static_cast<std::uint16_t>(
                    starfox_work_ram_read8(
                        address + 1U))
                << 8U
            );
    };


    // ========================================================
    // READ NATIVE LINKED LIST
    // ========================================================

    const auto read_list =
        [this,
         &starfox_work_ram_read16](
            std::uint16_t pointer) {

        std::vector<ObjectHandle> result;

        result.reserve(
            object_count_);

        std::array<
            bool,
            kMaximumObjects + 1>
            seen{};


        while (pointer != 0U) {

            const auto handle =
                native_object_handle(
                    pointer);

            if (handle == 0U
                || seen[handle]) {

                throw std::runtime_error{
                    "native 65C816 produced "
                    "an invalid object list"};
            }

            seen[handle] =
                true;

            result.push_back(
                handle);

            pointer =
                starfox_work_ram_read16(
                    pointer);
        }

        return result;
    };


    auto active =
        read_list(
            starfox_work_ram_read16(
                active_list_));

    auto free =
        read_list(
            starfox_work_ram_read16(
                free_list_));


    if (active.size()
            + free.size()
        != object_count_) {

        throw std::runtime_error{
            "native active/free lists "
            "do not cover the object pool"};
    }


    // ========================================================
    // LIST RESTORE ONLY WHEN NECESSARY
    //
    // ObjectPool::restore_lists() rebuilds all slot links and scans
    // the complete pool. Most strategy calls do not modify either
    // linked list, so avoid that work in the common case.
    // ========================================================

    const auto current_active =
        objects_->active_handles();

    const auto current_free =
        objects_->free_handles();


    const bool lists_changed =
        active != current_active
        || free != current_free;


    if (lists_changed) {

        objects_->restore_lists(
            active,
            free);
    }


    // ========================================================
    // IMPORT ACTIVE OBJECTS
    // ========================================================

    for (const auto handle :
         active) {

        const auto base =
            static_cast<std::uint32_t>(
                object_base_)
            + static_cast<std::uint32_t>(
                handle - 1U)
                * object_size_;


        const auto extended_base =
            extended_object_base_
            + static_cast<std::uint32_t>(
                handle - 1U)
                * object_size_;


        // ====================================================
        // BASE OBJECT BLOCK
        //
        // Pointer fields are imported separately below because the
        // 65816 stores ALBLKS addresses while GameObject stores handles.
        // ====================================================

        for (std::uint16_t offset = 4U;
             offset < object_size_;
             ++offset) {

            const bool pointer_field =
                (offset >= 6U
                    && offset <= 7U)

                || (offset >= 25U
                    && offset <= 28U);


            if (pointer_field) {
                continue;
            }


            const auto native_value =
                starfox_work_ram_read8(
                    base + offset);


            if (read_native_object_byte(
                    handle,
                    offset)
                == native_value) {

                continue;
            }


            write_native_object_byte(
                handle,
                offset,
                native_value);
        }


        auto& object =
            objects_->at(
                handle);


        // ====================================================
        // BASE POINTER FIELDS
        // ====================================================

        const auto attached =
            object_handle(
                starfox_work_ram_read16(
                    base + 6U));


        if (object.attached
            != attached) {

            object.attached =
                attached;
        }


        const auto immune_object =
            object_handle(
                starfox_work_ram_read16(
                    base + 25U));


        if (object.immune_object
            != immune_object) {

            object.immune_object =
                immune_object;
        }


        const auto collision_object =
            object_handle(
                starfox_work_ram_read16(
                    base + 27U));


        if (object.collision_object
            != collision_object) {

            object.collision_object =
                collision_object;
        }


        // ====================================================
        // EXTENDED OBJECT BLOCK
        // ====================================================

        for (std::size_t offset = 0U;
             offset < extended_object_bytes_;
             ++offset) {

            const auto native_value =
                starfox_work_ram_read8(
                    extended_base
                    + static_cast<std::uint32_t>(
                        offset));


            if (object.extended[
                    offset]
                == native_value) {

                continue;
            }


            objects_->write_path_byte(
                handle,

                static_cast<std::uint8_t>(
                    0x80U
                    + offset),

                native_value);
        }


        // ====================================================
        // SEMANTIC MIRRORS
        //
        // write_path_byte normally maintains these semantic members.
        // Refreshing them here unconditionally also covers the case
        // where host-side code changed a semantic field directly while
        // the backing extended byte itself did not change.
        // ====================================================

        object.strategy_state =
            object.extended[18U];


        const auto fire_object =
            object_handle(
                starfox_work_ram_read16(
                    extended_base
                    + 19U));


        if (object.fire_object
            != fire_object) {

            object.fire_object =
                fire_object;
        }


        const auto ex_shift =
            object_size_ == 57U
            ? std::size_t{2U}
            : std::size_t{};


        object.colour_frame =
            object.extended[
                28U + ex_shift];


        object.animation_frame =
            object.extended[
                29U + ex_shift];


        object.sound1 =
            object.extended[
                30U + ex_shift];


        object.sound2 =
            object.extended[
                31U + ex_shift];


        object.colour_table =
            static_cast<std::uint16_t>(
                object.extended[
                    32U + ex_shift])

            | (
                static_cast<std::uint16_t>(
                    object.extended[
                        33U + ex_shift])
                << 8U
            );


        object.texture_scroll_x =
            object.extended[
                42U + ex_shift];


        object.texture_scroll_y =
            object.extended[
                43U + ex_shift];
    }
}
'''

    text = (
        text[:start]
        + new_function
        + text[end:]
    )

    path.write_text(
        text,
        encoding="utf-8"
    )

    print(
        "PATCH   sync_objects_from_cpu:"
    )

    print(
        "        change-aware import instalado"
    )

    print(
        "        list restore somente quando alterada"
    )

    print(
        "        base bytes somente quando alterados"
    )

    print(
        "        extended bytes somente quando alterados"
    )


print()
print(
    "Performance Pass 11 instalada."
)
PY


echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check


echo
echo "Marcador Pass 11:"
grep -n \
    'PASS11_CHANGE_AWARE_SYNC_FROM' \
    src/simulation/map_vm.cpp


echo
echo
echo "Change-aware checks:"
grep -n \
    'lists_changed\|native_value\|current_active\|current_free' \
    src/simulation/map_vm.cpp \
    | head -n 120


echo
echo
echo "Diff:"
git diff \
    --stat \
    src/simulation/map_vm.cpp


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
echo "PASS 11 CONCLUÍDA"
echo "============================================================"

echo
echo "Otimizações:"
echo "  [✓] mantém CPU -> host após cada native call"
echo "  [✓] evita restore_lists quando listas não mudaram"
echo "  [✓] evita write_base_byte para bytes idênticos"
echo "  [✓] evita write_path_byte para bytes idênticos"
echo "  [✓] preserva semantic mirrors"
echo "  [✓] preserva lógica 20 Hz"
echo "  [✓] preserva renderer 60 Hz"
echo
echo "Profiler mantido:"
echo "  [SFE PERF5]"
echo
echo "Métrica principal:"
echo "  sync_from"
echo "  sync_from_call"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "IMPORTANTE:"
echo "  ainda NÃO foi criado commit."
echo "  teste novamente SEM gravação de vídeo."
echo


{
    echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 11"
    echo
    echo "Optimization:"
    echo "  Change-aware CPU -> host object synchronization"
    echo "  Conditional ObjectPool list restore"
    echo "  Conditional base-byte import"
    echo "  Conditional extended-byte import"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Profiler:"
    echo "  [SFE PERF5]"
} > "$REPORT_DIR/report-share.txt"


echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"

echo
echo "Git status:"
git status --short
