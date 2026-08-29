#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-phase3b-reports/$STAMP"
FULL_LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"
BACKUP_DIR="$REPORT_DIR/backup"

mkdir -p "$REPORT_DIR" "$BACKUP_DIR"

cd "$PROJECT_ROOT"

exec > >(tee -a "$FULL_LOG") 2>&1

FINAL_RC=0

line() {
    printf '%s\n' \
        "============================================================"
}

section() {
    echo
    line
    echo "$1"
    line
}

generate_report() {
    {
        echo "STAR FOX ENHANCED — PT-BR FASE 03B"
        echo
        echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
        echo "Projeto: $PROJECT_ROOT"
        echo "Build:   $BUILD_DIR"
        echo "Código:  $FINAL_RC"

        echo
        echo "============================================================"
        echo "GIT STATUS"
        echo "============================================================"

        git status --short || true

        echo
        echo "============================================================"
        echo "DIFF STAT"
        echo "============================================================"

        git diff --stat || true

        echo
        echo "============================================================"
        echo "FERRAMENTAS"
        echo "============================================================"

        for file in \
            "$BUILD_DIR/starfox_dialogue_probe" \
            tools/scripts/ptbr-dialogue-discovery.sh \
            tools/scripts/ptbr-dialogue-probe.sh
        do
            if [[ -e "$file" ]]; then
                echo "OK      $file"
            else
                echo "AUSENTE $file"
            fi
        done

        echo
        echo "============================================================"
        echo "ULTIMAS 160 LINHAS"
        echo "============================================================"

        tail -n 160 "$FULL_LOG" || true

    } > "$REPORT"

    echo
    line
    echo "RELATORIO"
    line
    echo
    echo "$REPORT"
}

on_exit() {
    local rc=$?

    trap - EXIT

    if [[ "$FINAL_RC" -eq 0 && "$rc" -ne 0 ]]; then
        FINAL_RC="$rc"
    fi

    generate_report

    exit "$FINAL_RC"
}

trap on_exit EXIT

section "STAR FOX ENHANCED — PT-BR FASE 03B"

# ============================================================
# ETAPA 1 — preflight
# ============================================================

section "ETAPA 1 — PREFLIGHT"

for file in \
    CMakeLists.txt \
    include/starfox/assets/rom.hpp \
    localization/pt_BR/dialogue.tsv \
    include/starfox/localization/dialogue_catalog.hpp \
    src/localization/dialogue_catalog.cpp
do
    if [[ ! -s "$file" ]]; then
        echo "ERRO: arquivo necessário ausente:"
        echo "  $file"

        FINAL_RC=10
        exit "$FINAL_RC"
    fi

    echo "OK      $file"
done

if ! grep -q \
    'starfox_dialogue_catalog_tests' \
    CMakeLists.txt
then
    echo "ERRO: Fase 03 não detectada."

    FINAL_RC=11
    exit "$FINAL_RC"
fi

echo
echo "Fase 03 detectada."

# ============================================================
# ETAPA 2 — backup
# ============================================================

section "ETAPA 2 — BACKUP"

cp -a \
    CMakeLists.txt \
    "$BACKUP_DIR/CMakeLists.txt"

# ============================================================
# ETAPA 3 — dialogue probe
# ============================================================

section "ETAPA 3 — STARFOX_DIALOGUE_PROBE"

touch src/app/dialogue_probe.cpp

cat > src/app/dialogue_probe.cpp <<'CPP_EOF'
#include "starfox/assets/rom.hpp"

#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

constexpr std::size_t maximum_dialogue_bytes = 192U;

std::uint32_t parse_address(
    std::string_view text) {

    if (text.empty()) {
        throw std::invalid_argument{
            "empty dialogue address"};
    }

    std::size_t parsed{};

    const auto value =
        std::stoull(
            std::string{text},
            &parsed,
            0);

    if (parsed != text.size()
        || value > 0xffffffULL) {

        throw std::invalid_argument{
            "dialogue address must be a 24-bit SNES address"};
    }

    const auto address =
        static_cast<std::uint32_t>(value);

    if ((address & 0xffffU) < 0x8000U) {
        throw std::invalid_argument{
            "dialogue address is outside the LoROM ROM window"};
    }

    return address;
}

std::string hexadecimal(
    std::uint32_t value,
    std::size_t digits) {

    std::ostringstream output;

    output
        << std::uppercase
        << std::hex
        << std::setw(
            static_cast<int>(digits))
        << std::setfill('0')
        << value;

    return output.str();
}

std::string printable_dialogue(
    const starfox::assets::RomImage& rom,
    std::uint32_t address,
    bool& terminated,
    bool& truncated) {

    std::string output;

    output.reserve(
        maximum_dialogue_bytes);

    terminated = false;
    truncated = false;

    for (std::size_t offset = 1U;
         offset <= maximum_dialogue_bytes;
         ++offset) {

        const auto byte =
            rom.read8(
                address
                + static_cast<std::uint32_t>(
                    offset));

        if (byte == 0U) {
            terminated = true;
            break;
        }

        if (byte == '\r'
            || byte == '\n') {

            output += "\\n";
            continue;
        }

        if (byte == '\t') {
            output += "\\t";
            continue;
        }

        if (byte == '\\') {
            output += "\\\\";
            continue;
        }

        if (byte >= 32U
            && byte <= 126U) {

            output.push_back(
                static_cast<char>(byte));

            continue;
        }

        output += "\\x";
        output += hexadecimal(
            byte,
            2U);
    }

    if (!terminated) {
        truncated = true;
    }

    return output;
}

void usage(
    const char* program) {

    std::cerr
        << "Uso:\n"
        << "  "
        << program
        << " <SF.SFC> <endereco>\n\n"
        << "Exemplo:\n"
        << "  "
        << program
        << " upstream-ultrastarfox/SF.SFC"
        << " 0x2D8000\n";
}

} // namespace

int main(
    int argc,
    char** argv) {

    if (argc != 3) {
        usage(argv[0]);
        return 2;
    }

    try {
        const auto rom =
            starfox::assets::RomImage::load(
                argv[1]);

        const auto address =
            parse_address(
                argv[2]);

        const auto colour =
            rom.read8(address);

        bool terminated{};
        bool truncated{};

        const auto dialogue =
            printable_dialogue(
                rom,
                address,
                terminated,
                truncated);

        std::cout
            << "STAR FOX DIALOGUE PROBE\n"
            << '\n'
            << "ADDRESS  0x"
            << hexadecimal(address, 6U)
            << '\n'
            << "COLOUR   0x"
            << hexadecimal(colour, 2U)
            << '\n'
            << "LENGTH   "
            << dialogue.size()
            << '\n'
            << "STATUS   "
            << (terminated
                    ? "TERMINATED"
                    : "LIMIT REACHED")
            << '\n'
            << '\n'
            << "TEXT\n"
            << "------------------------------------------------------------\n"
            << dialogue
            << '\n';

        if (truncated) {
            std::cout
                << '\n'
                << "AVISO: visualização limitada a "
                << maximum_dialogue_bytes
                << " bytes.\n";
        }

        return 0;

    } catch (const std::exception& error) {
        std::cerr
            << "starfox_dialogue_probe: "
            << error.what()
            << '\n';

        return 1;
    }
}
CPP_EOF

# ============================================================
# ETAPA 4 — CMake
# ============================================================

section "ETAPA 4 — CMAKE"

python3 <<'PY'
from pathlib import Path

path = Path("CMakeLists.txt")

text = path.read_text(
    encoding="utf-8"
)

target = '''add_executable(
    starfox_dialogue_probe
    src/app/dialogue_probe.cpp)

target_link_libraries(
    starfox_dialogue_probe
    PRIVATE starfox_core)
'''

if "add_executable(\n    starfox_dialogue_probe" in text:
    print(
        "Target starfox_dialogue_probe já existe."
    )

else:
    anchor = '''add_executable(starfox_shape_preview src/app/shape_preview.cpp)
target_link_libraries(starfox_shape_preview PRIVATE starfox_core)
'''

    if anchor not in text:
        raise RuntimeError(
            "Não encontrei starfox_shape_preview em CMakeLists.txt"
        )

    replacement = (
        anchor
        + "\n"
        + target
        + "\n"
    )

    text = text.replace(
        anchor,
        replacement,
        1
    )

    path.write_text(
        text,
        encoding="utf-8"
    )

    print(
        "Target starfox_dialogue_probe adicionado."
    )
PY

# ============================================================
# ETAPA 5 — helper de probe
# ============================================================

section "ETAPA 5 — HELPER DE PROBE"

touch tools/scripts/ptbr-dialogue-probe.sh

cat > tools/scripts/ptbr-dialogue-probe.sh <<'SCRIPT_EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

cd "$PROJECT_ROOT"

if [[ "$#" -ne 1 ]]; then
    echo "Uso:"
    echo
    echo "  ./tools/scripts/ptbr-dialogue-probe.sh 0xENDERECO"
    echo

    exit 2
fi

ADDRESS="$1"

ROM="$PROJECT_ROOT/upstream-ultrastarfox/SF.SFC"
PROBE="$BUILD_DIR/starfox_dialogue_probe"

if [[ ! -x "$PROBE" ]]; then
    echo "ERRO: starfox_dialogue_probe ainda não foi compilado."
    exit 10
fi

if [[ ! -s "$ROM" ]]; then
    echo "ERRO: SF.SFC ausente."
    exit 11
fi

exec \
    "$PROBE" \
    "$ROM" \
    "$ADDRESS"
SCRIPT_EOF

chmod +x \
    tools/scripts/ptbr-dialogue-probe.sh

# ============================================================
# ETAPA 6 — discovery helper
# ============================================================

section "ETAPA 6 — DISCOVERY HELPER"

touch tools/scripts/ptbr-dialogue-discovery.sh

cat > tools/scripts/ptbr-dialogue-discovery.sh <<'SCRIPT_EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"

OUTPUT_DIR="$PROJECT_ROOT/out/ptbr-dialogue-discovery/$STAMP"

mkdir -p "$OUTPUT_DIR"

LOG="$OUTPUT_DIR/runtime.log"
ADDRESSES="$OUTPUT_DIR/addresses.txt"
COMMANDS="$OUTPUT_DIR/probe-commands.txt"

echo "============================================================"
echo "STAR FOX ENHANCED — DESCOBERTA DE DIALOGOS PT-BR"
echo "============================================================"
echo
echo "Log:"
echo "  $LOG"
echo
echo "Jogue normalmente."
echo "Ao terminar, feche a janela do jogo."
echo

set +e

STARFOX_LOG_MISSING_TRANSLATIONS=1 \
STARFOX_TEST_LANGUAGE=PT_BR \
"$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    BOOT \
    2> >(tee "$LOG" >&2)

GAME_RC=$?

set -e

grep \
    'PT-BR missing dialogue:' \
    "$LOG" \
    | sed 's/.*0x/0x/' \
    | tr '[:lower:]' '[:upper:]' \
    | sort -u \
    > "$ADDRESSES" \
    || true

: > "$COMMANDS"

while IFS= read -r address
do
    [[ -z "$address" ]] && continue

    printf \
        './tools/scripts/ptbr-dialogue-probe.sh %s\n' \
        "$address" \
        >> "$COMMANDS"

done < "$ADDRESSES"

COUNT="$(
    grep -c . "$ADDRESSES" \
        2>/dev/null \
        || true
)"

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"
echo
echo "Código do jogo:"
echo "  $GAME_RC"
echo
echo "Diálogos distintos encontrados:"
echo "  $COUNT"
echo
echo "Endereços:"
echo "  $ADDRESSES"
echo
echo "Comandos de inspeção:"
echo "  $COMMANDS"
echo

if [[ -s "$ADDRESSES" ]]; then
    cat "$ADDRESSES"

    echo
    echo "Para examinar uma fala:"
    echo
    head -n 1 "$COMMANDS"
else
    echo "Nenhum diálogo não traduzido foi encontrado nesta execução."
fi

exit 0
SCRIPT_EOF

chmod +x \
    tools/scripts/ptbr-dialogue-discovery.sh

# ============================================================
# ETAPA 7 — sintaxe
# ============================================================

section "ETAPA 7 — VALIDACAO DE SINTAXE"

bash -n \
    tools/scripts/ptbr-dialogue-probe.sh

bash -n \
    tools/scripts/ptbr-dialogue-discovery.sh

echo "Scripts shell: OK"

git diff --check

echo "git diff --check: OK"

# ============================================================
# ETAPA 8 — reconfigurar
# ============================================================

section "ETAPA 8 — CONFIGURACAO"

cmake \
    -S "$PROJECT_ROOT" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_EMBED_RUNTIME_ASSETS=OFF

# ============================================================
# ETAPA 9 — build
# ============================================================

section "ETAPA 9 — BUILD"

cmake \
    --build "$BUILD_DIR" \
    -j"$(nproc)"

# ============================================================
# ETAPA 10 — smoke do probe
# ============================================================

section "ETAPA 10 — PROBE"

if [[ ! -x "$BUILD_DIR/starfox_dialogue_probe" ]]; then
    echo "ERRO: starfox_dialogue_probe não foi criado."

    FINAL_RC=20
    exit "$FINAL_RC"
fi

"$BUILD_DIR/starfox_dialogue_probe" \
    2>&1 \
    | head -n 20 \
    || true

# ============================================================
# ETAPA 11 — suite
# ============================================================

section "ETAPA 11 — CTEST"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure

# ============================================================
# Resultado
# ============================================================

section "PT-BR FASE 03B CONCLUIDA"

echo "Ferramentas instaladas:"
echo
echo "  tools/scripts/ptbr-dialogue-discovery.sh"
echo "  tools/scripts/ptbr-dialogue-probe.sh"
echo
echo "  $BUILD_DIR/starfox_dialogue_probe"
echo
echo "Próximo comando:"
echo
echo "  ./tools/scripts/ptbr-dialogue-discovery.sh"

FINAL_RC=0

exit 0
