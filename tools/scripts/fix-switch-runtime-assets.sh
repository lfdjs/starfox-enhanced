#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"
BUILD_DIR="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"

REPORT_DIR="$PROJECT_ROOT/out/switch-runtime-assets-fix/$STAMP"

mkdir -p "$REPORT_DIR"

cp -a \
  "$SOURCE" \
  "$REPORT_DIR/starfox_pc.cpp.before"

export SOURCE

python3 <<'PY'
from pathlib import Path
import os

path = Path(os.environ["SOURCE"])

text = path.read_text(
    encoding="utf-8"
)

# ============================================================
# 1. Checkpoint depois da janela
# ============================================================

old = '''        Window window;
        const auto platform_profile = starfox::app::runtime_platform_profile();
'''

new = '''        Window window;

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] Window construction complete\\n");

        {
            std::string argument_message{
                "[SFE SWITCH] argc="};

            argument_message += std::to_string(argc);

            if (argc > 0
                && argv != nullptr
                && argv[0] != nullptr) {

                argument_message += " argv0=";
                argument_message += argv[0];
            }

            argument_message += "\\n";

            switch_runtime_debug(
                argument_message);
        }

        switch_runtime_debug(
            "[SFE SWITCH] before runtime_platform_profile\\n");
#endif

        const auto platform_profile =
            starfox::app::runtime_platform_profile();

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] runtime_platform_profile OK\\n");
#endif
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "Não encontrei Window/platform_profile."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   checkpoints pós-Window"
    )
else:
    print(
        "JA OK   checkpoints pós-Window"
    )


# ============================================================
# 2. Carregamento de assets específico do Switch
# ============================================================

anchor = '''        const auto original_assets = [&]() -> RuntimeAssets {
            if (argc == 1 || argc == 2) {
'''

replacement = '''        const auto original_assets = [&]() -> RuntimeAssets {

#if defined(STARFOX_SWITCH_RUNTIME)

            constexpr const char* switch_rom_path =
                "sdmc:/switch/starfox-enhanced/SF.SFC";

            constexpr const char* switch_symbols_path =
                "sdmc:/switch/starfox-enhanced/SYMBOLS.TXT";

            switch_runtime_debug(
                "[SFE SWITCH] resolving Original runtime assets\\n");

            switch_runtime_debug(
                "[SFE SWITCH] ROM: sdmc:/switch/starfox-enhanced/SF.SFC\\n");

            switch_runtime_debug(
                "[SFE SWITCH] SYMBOLS: sdmc:/switch/starfox-enhanced/SYMBOLS.TXT\\n");

            // Probe with ordinary streams first. This intentionally avoids
            // std::filesystem::absolute/current_path on Switch.
            {
                std::ifstream rom_probe{
                    switch_rom_path,
                    std::ios::binary};

                if (!rom_probe) {
                    switch_runtime_debug(
                        "[SFE SWITCH] ERROR: SF.SFC not found on sdmc\\n");

                    throw std::runtime_error{
                        "SF.SFC not found at "
                        "sdmc:/switch/starfox-enhanced/SF.SFC"};
                }
            }

            switch_runtime_debug(
                "[SFE SWITCH] SF.SFC accessible\\n");

            {
                std::ifstream symbols_probe{
                    switch_symbols_path};

                if (!symbols_probe) {
                    switch_runtime_debug(
                        "[SFE SWITCH] ERROR: SYMBOLS.TXT not found on sdmc\\n");

                    throw std::runtime_error{
                        "SYMBOLS.TXT not found at "
                        "sdmc:/switch/starfox-enhanced/SYMBOLS.TXT"};
                }
            }

            switch_runtime_debug(
                "[SFE SWITCH] SYMBOLS.TXT accessible\\n");

            switch_runtime_debug(
                "[SFE SWITCH] before load_external_assets\\n");

            auto switch_assets =
                load_external_assets(
                    switch_rom_path,
                    switch_symbols_path);

            switch_runtime_debug(
                "[SFE SWITCH] Original runtime assets loaded OK\\n");

            return switch_assets;

#endif

            if (argc == 1 || argc == 2) {
'''

if replacement not in text:

    if anchor not in text:
        raise RuntimeError(
            "Não encontrei original_assets lambda."
        )

    text = text.replace(
        anchor,
        replacement,
        1
    )

    print(
        "PATCH   assets Switch via sdmc"
    )
else:
    print(
        "JA OK   assets Switch via sdmc"
    )


path.write_text(
    text,
    encoding="utf-8"
)

print()
print("Patch aplicado.")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

grep -n \
  -A100 \
  -B10 \
  'resolving Original runtime assets' \
  src/app/starfox_pc.cpp \
  | head -n 140

echo
echo "============================================================"
echo "BUILD"
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
echo "NRO"
echo "============================================================"

ls -lh "$NRO"

grep -aob \
  'NRO0\|ASET' \
  "$NRO"

sha256sum \
  "$NRO" \
  | tee "$REPORT_DIR/sha256.txt"

{
    echo "STAR FOX ENHANCED — SWITCH ASSET PATH"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "Guest asset path:"
    echo "  sdmc:/switch/starfox-enhanced/SF.SFC"
    echo "  sdmc:/switch/starfox-enhanced/SYMBOLS.TXT"
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
