#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf10-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-native-sync-pass10/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 10"
echo "NATIVE OBJECT SYNC OPTIMIZATION"
echo "============================================================"
echo

FILES=(
    include/starfox/simulation/wdc65816.hpp
    include/starfox/simulation/map_vm.hpp
    src/simulation/wdc65816.cpp
    src/simulation/map_vm.cpp
    src/simulation/strategy_scheduler.cpp
)

for file in "${FILES[@]}"
do
    test -f "$file" || {
        echo "ERRO: arquivo não encontrado:"
        echo "  $file"
        exit 10
    }

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


# ============================================================
# HELPERS
# ============================================================

def load(relative):
    path = root / relative
    return path, path.read_text(
        encoding="utf-8"
    )


def save(path, text):
    path.write_text(
        text,
        encoding="utf-8"
    )


def section(
    text,
    start_token,
    end_token):

    start = text.find(
        start_token
    )

    if start < 0:
        raise RuntimeError(
            f"Token inicial ausente: "
            f"{start_token}"
        )

    end = text.find(
        end_token,
        start
    )

    if end < 0:
        raise RuntimeError(
            f"Token final ausente: "
            f"{end_token}"
        )

    return start, end


# ============================================================
# WDC65816.HPP
#
# Expor somente a WRAM já pertencente ao adaptador.
# Não muda memória nem mapeamento.
# ============================================================

path, text = load(
    "include/starfox/simulation/wdc65816.hpp"
)

if "work_ram() noexcept" not in text:

    needle = '''    void write16(std::uint32_t address, std::uint16_t value);
'''

    replacement = '''    void write16(std::uint32_t address, std::uint16_t value);

    // Direct host view of the SNES work RAM.
    //
    // Performance-sensitive compatibility code may use this only for
    // addresses that are already known to resolve to WRAM. This avoids
    // repeatedly traversing the generic SystemBus for bulk object-state
    // synchronization while preserving the exact underlying storage.
    [[nodiscard]] std::span<std::uint8_t> work_ram() noexcept;
    [[nodiscard]] std::span<const std::uint8_t> work_ram() const noexcept;
'''

    if needle not in text:
        raise RuntimeError(
            "Ponto de inserção de work_ram "
            "não encontrado em wdc65816.hpp"
        )

    text = text.replace(
        needle,
        replacement,
        1
    )

    print(
        "PATCH   Wdc65816::work_ram API"
    )

else:

    print(
        "JA OK   Wdc65816::work_ram API"
    )

save(
    path,
    text
)


# ============================================================
# WDC65816.CPP
# ============================================================

path, text = load(
    "src/simulation/wdc65816.cpp"
)

if "Wdc65816::work_ram() noexcept" not in text:

    needle = '''void Wdc65816::write16(std::uint32_t address, std::uint16_t value) {
    write8(address, static_cast<std::uint8_t>(value));
    write8(address + 1U, static_cast<std::uint8_t>(value >> 8U));
}
'''

    replacement = needle + '''

std::span<std::uint8_t> Wdc65816::work_ram() noexcept {
    return impl_->wram;
}

std::span<const std::uint8_t> Wdc65816::work_ram() const noexcept {
    return impl_->wram;
}
'''

    if needle not in text:
        raise RuntimeError(
            "Implementação de write16 não encontrada "
            "em wdc65816.cpp"
        )

    text = text.replace(
        needle,
        replacement,
        1
    )

    print(
        "PATCH   direct WRAM implementation"
    )

else:

    print(
        "JA OK   direct WRAM implementation"
    )

save(
    path,
    text
)


# ============================================================
# MAP_VM.HPP
#
# Batch de chamadas nativas de objetos.
#
# A CPU recebe o ObjectPool uma vez no início do lote.
# Depois disso WRAM já representa o último estado.
# ============================================================

path, text = load(
    "include/starfox/simulation/map_vm.hpp"
)

if "begin_native_object_batch()" not in text:

    needle = '''    std::size_t call_native_object_routine(
'''

    replacement = '''    // Batch consecutive native object calls.
    //
    // sync_objects_to_cpu() is performed once on entry. Individual
    // call_native_object_routine() calls still synchronize CPU -> host
    // afterward, preserving the scheduler's host-side view of active lists,
    // removals, attachments and strategy state.
    void begin_native_object_batch();
    void end_native_object_batch() noexcept;

    std::size_t call_native_object_routine(
'''

    if needle not in text:
        raise RuntimeError(
            "call_native_object_routine não encontrada "
            "em map_vm.hpp"
        )

    text = text.replace(
        needle,
        replacement,
        1
    )

    print(
        "PATCH   MapVm native batch API"
    )

else:

    print(
        "JA OK   MapVm native batch API"
    )


if "native_object_batch_active_" not in text:

    needle = '''    Wdc65816 cpu_;
'''

    replacement = '''    bool native_object_batch_active_{};
    Wdc65816 cpu_;
'''

    if needle not in text:
        raise RuntimeError(
            "Campo cpu_ não encontrado "
            "em map_vm.hpp"
        )

    text = text.replace(
        needle,
        replacement,
        1
    )

    print(
        "PATCH   MapVm batch state"
    )

else:

    print(
        "JA OK   MapVm batch state"
    )

save(
    path,
    text
)


# ============================================================
# MAP_VM.CPP — DIRECT WRAM SYNC
# ============================================================

path, text = load(
    "src/simulation/map_vm.cpp"
)


# ------------------------------------------------------------
# sync_objects_to_cpu
# ------------------------------------------------------------

start, end = section(
    text,
    "void MapVm::sync_objects_to_cpu()",
    "\nvoid MapVm::sync_objects_from_cpu()"
)

block = text[start:end]

if "starfox_work_ram_write8" not in block:

    brace = block.find("{")

    if brace < 0:
        raise RuntimeError(
            "Corpo de sync_objects_to_cpu não encontrado"
        )

    helpers = r'''
    auto work_ram =
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

        // Banks $00-$3f/$80-$bf mirror the first 8 KiB
        // of WRAM. Native object records and list heads live
        // in this range.
        return static_cast<std::size_t>(
            address & 0x1fffU);
    };

    const auto starfox_work_ram_write8 =
        [&work_ram,
         &starfox_work_ram_offset](
            std::uint32_t address,
            std::uint8_t value) noexcept {

        work_ram[
            starfox_work_ram_offset(
                address)] =
            value;
    };

    const auto starfox_work_ram_write16 =
        [&starfox_work_ram_write8](
            std::uint32_t address,
            std::uint16_t value) noexcept {

        starfox_work_ram_write8(
            address,
            static_cast<std::uint8_t>(
                value));

        starfox_work_ram_write8(
            address + 1U,
            static_cast<std::uint8_t>(
                value >> 8U));
    };
'''

    block = (
        block[:brace + 1]
        + helpers
        + block[brace + 1:]
    )

    block = block.replace(
        "cpu_.write16(",
        "starfox_work_ram_write16("
    )

    block = block.replace(
        "cpu_.write8(",
        "starfox_work_ram_write8("
    )

    text = (
        text[:start]
        + block
        + text[end:]
    )

    print(
        "PATCH   sync_objects_to_cpu direct WRAM"
    )

else:

    print(
        "JA OK   sync_objects_to_cpu direct WRAM"
    )


# Reload positions after first modification.
start, end = section(
    text,
    "void MapVm::sync_objects_from_cpu()",
    "\nvoid MapVm::execute_inline_65816()"
)

block = text[start:end]


if "starfox_work_ram_read8" not in block:

    brace = block.find("{")

    if brace < 0:
        raise RuntimeError(
            "Corpo de sync_objects_from_cpu não encontrado"
        )

    helpers = r'''
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
'''

    block = (
        block[:brace + 1]
        + helpers
        + block[brace + 1:]
    )

    block = block.replace(
        "cpu_.read16(",
        "starfox_work_ram_read16("
    )

    block = block.replace(
        "cpu_.read8(",
        "starfox_work_ram_read8("
    )

    text = (
        text[:start]
        + block
        + text[end:]
    )

    print(
        "PATCH   sync_objects_from_cpu direct WRAM"
    )

else:

    print(
        "JA OK   sync_objects_from_cpu direct WRAM"
    )


# ============================================================
# MAP_VM.CPP — BATCH IMPLEMENTATION
# ============================================================

if "void MapVm::begin_native_object_batch()" not in text:

    token = (
        "std::size_t "
        "MapVm::call_native_object_routine("
    )

    position = text.find(
        token
    )

    if position < 0:
        raise RuntimeError(
            "call_native_object_routine não encontrada "
            "em map_vm.cpp"
        )

    implementation = r'''
void MapVm::begin_native_object_batch() {
    if (native_object_batch_active_) {
        throw std::logic_error{
            "native object batch is already active"};
    }

    // Establish a coherent host -> WRAM snapshot once.
    sync_objects_to_cpu();

    native_object_batch_active_ =
        true;
}

void MapVm::end_native_object_batch() noexcept {
    native_object_batch_active_ =
        false;
}

'''

    text = (
        text[:position]
        + implementation
        + text[position:]
    )

    print(
        "PATCH   native batch implementation"
    )

else:

    print(
        "JA OK   native batch implementation"
    )


# ============================================================
# SKIP REDUNDANT sync_objects_to_cpu() INSIDE A BATCH
# ============================================================

start, end = section(
    text,
    "std::size_t MapVm::call_native_object_routine(",
    "\nstd::size_t MapVm::call_native_routine("
)

block = text[start:end]

conditional = '''    if (!native_object_batch_active_) {
        sync_objects_to_cpu();
    }
'''

if conditional not in block:

    needle = "    sync_objects_to_cpu();\n"

    if needle not in block:
        raise RuntimeError(
            "sync_objects_to_cpu não encontrada dentro "
            "de call_native_object_routine"
        )

    block = block.replace(
        needle,
        conditional,
        1
    )

    text = (
        text[:start]
        + block
        + text[end:]
    )

    print(
        "PATCH   skip redundant host->WRAM sync"
    )

else:

    print(
        "JA OK   redundant host->WRAM sync skip"
    )


save(
    path,
    text
)


# ============================================================
# STRATEGY SCHEDULER — RAII BATCH
# ============================================================

path, text = load(
    "src/simulation/strategy_scheduler.cpp"
)


if "class NativeObjectBatchScope" not in text:

    needle = '''} // namespace

NativeStrategyScheduler::NativeStrategyScheduler(
'''

    replacement = r'''class NativeObjectBatchScope {
public:
    explicit NativeObjectBatchScope(
        MapVm& native_state)
        : native_state_(&native_state) {

        native_state_->begin_native_object_batch();
    }

    ~NativeObjectBatchScope() noexcept {
        native_state_->end_native_object_batch();
    }

    NativeObjectBatchScope(
        const NativeObjectBatchScope&) = delete;

    NativeObjectBatchScope& operator=(
        const NativeObjectBatchScope&) = delete;

private:
    MapVm* native_state_{};
};

} // namespace

NativeStrategyScheduler::NativeStrategyScheduler(
'''

    if needle not in text:
        raise RuntimeError(
            "Fim do namespace anônimo não encontrado "
            "em strategy_scheduler.cpp"
        )

    text = text.replace(
        needle,
        replacement,
        1
    )

    print(
        "PATCH   NativeObjectBatchScope"
    )

else:

    print(
        "JA OK   NativeObjectBatchScope"
    )


def add_batch_scope(
    source,
    function_token,
    marker):

    start = source.find(
        function_token
    )

    if start < 0:
        raise RuntimeError(
            f"Função ausente: {function_token}"
        )

    end = source.find(
        "\n}",
        start
    )

    search_end = min(
        len(source),
        start + 1800
    )

    if marker in source[
        start:search_end
    ]:

        print(
            f"JA OK   {function_token}"
        )

        return source

    brace = source.find(
        "{",
        start
    )

    if brace < 0:
        raise RuntimeError(
            f"Corpo ausente: {function_token}"
        )

    insertion = f'''
    NativeObjectBatchScope
        {marker}{{*native_state_}};
'''

    source = (
        source[:brace + 1]
        + insertion
        + source[brace + 1:]
    )

    print(
        f"PATCH   {function_token} batch"
    )

    return source


text = add_batch_scope(
    text,
    "StrategyTickStats NativeStrategyScheduler::tick_all()",
    "native_object_batch"
)

text = add_batch_scope(
    text,
    "StrategyTickStats NativeStrategyScheduler::tick_all_no_objects(",
    "native_no_objects_batch"
)


save(
    path,
    text
)


print()
print(
    "Performance Pass 10 installed."
)
PY


echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check


echo
echo "Direct WRAM:"
grep -R \
    -n \
    'work_ram()\|starfox_work_ram_' \
    include/starfox/simulation/wdc65816.hpp \
    src/simulation/wdc65816.cpp \
    src/simulation/map_vm.cpp \
    | head -n 160


echo
echo
echo "Native batching:"
grep -R \
    -n \
    'native_object_batch\|NativeObjectBatchScope' \
    include/starfox/simulation/map_vm.hpp \
    src/simulation/map_vm.cpp \
    src/simulation/strategy_scheduler.cpp \
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
echo "PASS 10 CONCLUÍDA"
echo "============================================================"

echo
echo "Alterações:"
echo "  [✓] acesso direto à WRAM no object sync"
echo "  [✓] host->WRAM uma vez por strategy batch"
echo "  [✓] WRAM->host ainda executado após cada native call"
echo "  [✓] sem alteração da cadência 20 Hz"
echo "  [✓] sem alteração do renderer"
echo "  [✓] sem alteração do áudio"
echo
echo "Profiler mantido:"
echo "  [SFE PERF5]"
echo
echo "Esperado:"
echo "  calls(sync_to) deve cair fortemente"
echo "  sync_to deve ficar próximo de zero"
echo "  sync_from_call também deve cair"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "IMPORTANTE:"
echo "  nenhum commit foi criado."
echo "  teste SEM captura de vídeo."
echo


{
    echo "STAR FOX ENHANCED — PERFORMANCE PASS 10"
    echo
    echo "Optimizations:"
    echo "  Direct WRAM object synchronization"
    echo "  Strategy native object batching"
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
