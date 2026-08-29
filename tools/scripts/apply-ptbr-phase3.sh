#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-phase3-reports/$STAMP"
BACKUP_DIR="$REPORT_DIR/backup"
FULL_LOG="$REPORT_DIR/full.log"
REPORT="$REPORT_DIR/report-share.txt"

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
        echo "STAR FOX ENHANCED — PT-BR FASE 03"
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
        echo "CATALOGO"
        echo "============================================================"

        if [[ -f localization/pt_BR/dialogue.tsv ]]; then
            cat localization/pt_BR/dialogue.tsv
        fi

        echo
        echo "============================================================"
        echo "ULTIMAS 180 LINHAS"
        echo "============================================================"

        tail -n 180 "$FULL_LOG" || true

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

section "STAR FOX ENHANCED — PT-BR FASE 03"

# ============================================================
# ETAPA 1 — preflight
# ============================================================

section "ETAPA 1 — PREFLIGHT"

for file in \
    CMakeLists.txt \
    include/starfox/render/scaled_text_renderer.hpp \
    src/render/scaled_text_renderer.cpp \
    include/starfox/localization/language.hpp \
    src/localization/language.cpp \
    src/app/starfox_pc.cpp
do
    if [[ ! -s "$file" ]]; then
        echo "ERRO: arquivo ausente:"
        echo "  $file"

        FINAL_RC=10
        exit "$FINAL_RC"
    fi

    echo "OK      $file"
done

echo
echo "Verificando Fase PT-BR 02..."

if ! grep -q 'draw_utf8' \
    include/starfox/render/scaled_text_renderer.hpp
then
    echo "ERRO: draw_utf8 nao encontrado."
    echo "A Fase PT-BR 02 precisa estar aplicada."

    FINAL_RC=11
    exit "$FINAL_RC"
fi

if ! grep -q 'PORTUGUÊS BR' \
    src/localization/language.cpp
then
    echo "ERRO: dicionario UTF-8 da Fase 02 nao encontrado."

    FINAL_RC=12
    exit "$FINAL_RC"
fi

echo "Fase PT-BR 02 detectada."

# ============================================================
# ETAPA 2 — backup
# ============================================================

section "ETAPA 2 — BACKUP"

for file in \
    CMakeLists.txt \
    include/starfox/render/scaled_text_renderer.hpp \
    src/render/scaled_text_renderer.cpp \
    src/app/starfox_pc.cpp \
    tests/localization_tests.cpp
do
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"

    cp -a \
        "$file" \
        "$BACKUP_DIR/$file"

    echo "BACKUP  $file"
done

# ============================================================
# ETAPA 3 — catálogo de diálogos
# ============================================================

section "ETAPA 3 — DIALOGUE CATALOG"

mkdir -p \
    include/starfox/localization \
    src/localization \
    localization/pt_BR

cat > include/starfox/localization/dialogue_catalog.hpp <<'HEADER_EOF'
#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

namespace starfox::localization {

class DialogueCatalog {
public:
    [[nodiscard]] bool load(
        const std::filesystem::path& path) noexcept;

    void clear() noexcept {
        entries_.clear();
    }

    [[nodiscard]] std::optional<std::string_view> find(
        std::uint32_t address) const noexcept;

    [[nodiscard]] std::size_t size() const noexcept {
        return entries_.size();
    }

    [[nodiscard]] bool empty() const noexcept {
        return entries_.empty();
    }

private:
    std::unordered_map<std::uint32_t, std::string> entries_;
};

} // namespace starfox::localization
HEADER_EOF

cat > src/localization/dialogue_catalog.cpp <<'CPP_EOF'
#include "starfox/localization/dialogue_catalog.hpp"

#include <fstream>
#include <limits>
#include <string>

namespace starfox::localization {
namespace {

std::string decode_escapes(std::string_view input) {
    std::string result;
    result.reserve(input.size());

    for (std::size_t index = 0U;
         index < input.size();
         ++index) {

        const auto character = input[index];

        if (character != '\\'
            || index + 1U >= input.size()) {

            result.push_back(character);
            continue;
        }

        const auto next = input[++index];

        switch (next) {
        case 'n':
            result.push_back('\n');
            break;

        case 't':
            result.push_back('\t');
            break;

        case '\\':
            result.push_back('\\');
            break;

        default:
            result.push_back('\\');
            result.push_back(next);
            break;
        }
    }

    return result;
}

} // namespace

bool DialogueCatalog::load(
    const std::filesystem::path& path) noexcept {

    try {
        std::ifstream input{path};

        if (!input) {
            return false;
        }

        std::unordered_map<std::uint32_t, std::string>
            loaded;

        std::string line;

        while (std::getline(input, line)) {
            if (!line.empty()
                && line.back() == '\r') {
                line.pop_back();
            }

            const auto first =
                line.find_first_not_of(" \t");

            if (first == std::string::npos
                || line[first] == '#') {
                continue;
            }

            const auto separator =
                line.find('\t', first);

            if (separator == std::string::npos) {
                return false;
            }

            const auto address_text =
                line.substr(
                    first,
                    separator - first);

            auto translation =
                line.substr(separator + 1U);

            if (translation.empty()) {
                return false;
            }

            std::size_t parsed{};

            const auto value =
                std::stoull(
                    address_text,
                    &parsed,
                    0);

            if (parsed != address_text.size()
                || value > 0xffffffULL) {
                return false;
            }

            loaded[
                static_cast<std::uint32_t>(value)] =
                    decode_escapes(translation);
        }

        entries_ = std::move(loaded);

        return true;

    } catch (...) {
        return false;
    }
}

std::optional<std::string_view>
DialogueCatalog::find(
    std::uint32_t address) const noexcept {

    const auto found =
        entries_.find(address);

    if (found == entries_.end()) {
        return std::nullopt;
    }

    return std::string_view{
        found->second
    };
}

} // namespace starfox::localization
CPP_EOF

cat > localization/pt_BR/dialogue.tsv <<'TSV_EOF'
# STAR FOX ENHANCED — DIÁLOGOS PT-BR
#
# Formato:
#
# 0xBBHHHH<TAB>Texto traduzido em UTF-8
#
# Exemplo de estrutura:
#
# 0x123456	Exemplo de tradução.
#
# Para quebra de linha explícita, use:
#
# \n
#
# Endereços sem tradução cadastrada usam automaticamente
# o texto original em inglês da ROM.
#
# Este arquivo começa sem falas do roteiro.
TSV_EOF

echo "Catálogo criado."

# ============================================================
# ETAPA 4 — teste do catálogo
# ============================================================

section "ETAPA 4 — TESTE DO CATALOGO"

cat > tests/dialogue_catalog_tests.cpp <<'CPP_EOF'
#include "starfox/localization/dialogue_catalog.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string_view>

namespace {

void require(
    bool condition,
    std::string_view message) {

    if (!condition) {
        std::cerr
            << "dialogue catalog test failed: "
            << message
            << '\n';

        std::exit(1);
    }
}

} // namespace

int main() {
    namespace fs = std::filesystem;

    const auto path =
        fs::temp_directory_path()
        / "starfox-enhanced-dialogue-test.tsv";

    {
        std::ofstream output{
            path,
            std::ios::trunc
        };

        output
            << "# teste\n"
            << "0x123456\tOlá, piloto!\n"
            << "0xabcdef\tLinha um\\\\nLinha dois\n";
    }

    starfox::localization::DialogueCatalog catalog;

    require(
        catalog.load(path),
        "catalog could not be loaded");

    require(
        catalog.size() == 2U,
        "catalog entry count is wrong");

    const auto first =
        catalog.find(0x123456U);

    require(
        first
            && *first == "Olá, piloto!",
        "UTF-8 translation was not preserved");

    const auto second =
        catalog.find(0xabcdefU);

    require(
        second
            && *second
                == "Linha um\nLinha dois",
        "escaped newline was not decoded");

    require(
        !catalog.find(0x111111U),
        "missing address unexpectedly resolved");

    std::error_code error;

    fs::remove(
        path,
        error);

    require(
        !error,
        "temporary catalog could not be removed");

    std::cout
        << "dialogue catalog tests passed\n";

    return 0;
}
CPP_EOF

# ============================================================
# ETAPA 5 — draw_utf8_wrapped
# ============================================================

section "ETAPA 5 — TEXTO UTF-8 COM QUEBRA"

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])

header = (
    root
    / "include/starfox/render/scaled_text_renderer.hpp"
)

cpp = (
    root
    / "src/render/scaled_text_renderer.cpp"
)

text = header.read_text(
    encoding="utf-8"
)

if "void draw_utf8_wrapped(" not in text:
    anchor = '''    [[nodiscard]] std::int32_t measure_utf8(
        std::string_view text) const;
'''

    addition = '''    [[nodiscard]] std::int32_t measure_utf8(
        std::string_view text) const;

    void draw_utf8_wrapped(
        std::string_view text,
        std::int32_t x,
        std::int32_t y,
        Framebuffer& target,
        std::uint8_t colour = 14U,
        std::uint8_t colour_index_base = 7U * 16U,
        std::int32_t right_clip = 224,
        std::size_t max_lines = 3U) const;
'''

    if anchor not in text:
        raise RuntimeError(
            "measure_utf8 nao encontrado no header."
        )

    text = text.replace(
        anchor,
        addition,
        1
    )

    header.write_text(
        text,
        encoding="utf-8"
    )

    print(
        "PATCH   scaled_text_renderer.hpp"
    )
else:
    print(
        "JA OK   draw_utf8_wrapped header"
    )

text = cpp.read_text(
    encoding="utf-8"
)

if "void ScaledTextRenderer::draw_utf8_wrapped(" not in text:
    marker = (
        "\n} // namespace starfox::render\n"
    )

    position = text.rfind(marker)

    if position < 0:
        raise RuntimeError(
            "namespace final do renderer nao encontrado."
        )

    implementation = r'''
void ScaledTextRenderer::draw_utf8_wrapped(
    std::string_view text,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour,
    std::uint8_t colour_index_base,
    std::int32_t right_clip,
    std::size_t max_lines) const {

    if (text.empty()
        || max_lines == 0U) {
        return;
    }

    const auto origin_x = x;

    std::string line;
    std::size_t lines{};

    const auto flush =
        [&]() -> bool {

        if (line.empty()) {
            return lines < max_lines;
        }

        if (lines >= max_lines) {
            return false;
        }

        draw_utf8(
            line,
            origin_x,
            y,
            target,
            colour,
            colour_index_base);

        line.clear();

        ++lines;
        y += 13;

        return lines < max_lines;
    };

    std::size_t offset{};

    while (offset < text.size()) {
        if (text[offset] == '\r') {
            ++offset;
            continue;
        }

        if (text[offset] == '\n') {
            if (!flush()) {
                return;
            }

            ++offset;
            continue;
        }

        while (offset < text.size()
            && text[offset] == ' ') {
            ++offset;
        }

        if (offset >= text.size()) {
            break;
        }

        if (text[offset] == '\n') {
            continue;
        }

        const auto begin = offset;

        while (offset < text.size()
            && text[offset] != ' '
            && text[offset] != '\n'
            && text[offset] != '\r') {

            ++offset;
        }

        const auto word =
            text.substr(
                begin,
                offset - begin);

        auto candidate =
            line.empty()
            ? std::string{word}
            : line + " "
                + std::string{word};

        if (!line.empty()
            && origin_x
                + measure_utf8(candidate)
                    > right_clip) {

            if (!flush()) {
                return;
            }

            line.assign(
                word.data(),
                word.size());

        } else {
            line =
                std::move(candidate);
        }
    }

    if (!line.empty()
        && lines < max_lines) {

        draw_utf8(
            line,
            origin_x,
            y,
            target,
            colour,
            colour_index_base);
    }
}
'''

    text = (
        text[:position]
        + "\n"
        + implementation
        + text[position:]
    )

    cpp.write_text(
        text,
        encoding="utf-8"
    )

    print(
        "PATCH   scaled_text_renderer.cpp"
    )
else:
    print(
        "JA OK   draw_utf8_wrapped implementation"
    )
PY

# ============================================================
# ETAPA 6 — CMake
# ============================================================

section "ETAPA 6 — CMAKE"

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])
path = root / "CMakeLists.txt"

text = path.read_text(
    encoding="utf-8"
)

if "src/localization/dialogue_catalog.cpp" not in text:
    anchor = (
        "    src/localization/language.cpp\n"
    )

    if anchor not in text:
        raise RuntimeError(
            "language.cpp nao encontrado no starfox_core."
        )

    text = text.replace(
        anchor,
        anchor
        + "    src/localization/dialogue_catalog.cpp\n",
        1
    )

    print(
        "PATCH   dialogue_catalog.cpp -> starfox_core"
    )

if "starfox_dialogue_catalog_tests" not in text:
    anchor = '''    add_executable(starfox_localization_tests tests/localization_tests.cpp)
    target_link_libraries(starfox_localization_tests PRIVATE starfox_core)
    add_test(NAME starfox_localization_tests COMMAND starfox_localization_tests)
'''

    addition = anchor + '''
    add_executable(
        starfox_dialogue_catalog_tests
        tests/dialogue_catalog_tests.cpp)

    target_link_libraries(
        starfox_dialogue_catalog_tests
        PRIVATE starfox_core)

    add_test(
        NAME starfox_dialogue_catalog_tests
        COMMAND starfox_dialogue_catalog_tests)
'''

    if anchor not in text:
        raise RuntimeError(
            "starfox_localization_tests nao encontrado."
        )

    text = text.replace(
        anchor,
        addition,
        1
    )

    print(
        "PATCH   dialogue catalog test"
    )

if 'DESTINATION "localization"' not in text:
    text += '''

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/localization")
    install(
        DIRECTORY
            "${CMAKE_CURRENT_SOURCE_DIR}/localization/"
        DESTINATION
            "localization")
endif()
'''

    print(
        "PATCH   install localization"
    )

path.write_text(
    text,
    encoding="utf-8"
)
PY

# ============================================================
# ETAPA 7 — integração no frontend
# ============================================================

section "ETAPA 7 — FRONTEND"

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])
path = root / "src/app/starfox_pc.cpp"

text = path.read_text(
    encoding="utf-8"
)


def replace_once(
    old,
    new,
    description
):
    global text

    if new in text:
        print(
            "JA OK   "
            + description
        )

        return

    if old not in text:
        raise RuntimeError(
            "Trecho nao encontrado: "
            + description
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   "
        + description
    )


# ------------------------------------------------------------
# include
# ------------------------------------------------------------

include_anchor = (
    '#include "starfox/localization/language.hpp"\n'
)

if (
    '#include "starfox/localization/dialogue_catalog.hpp"'
    not in text
):
    if include_anchor not in text:
        raise RuntimeError(
            "include language.hpp nao encontrado."
        )

    text = text.replace(
        include_anchor,
        '#include "starfox/localization/dialogue_catalog.hpp"\n'
        + include_anchor,
        1
    )

    print(
        "PATCH   include dialogue_catalog.hpp"
    )


# ------------------------------------------------------------
# catálogo após carregamento dos assets
# ------------------------------------------------------------

anchor = '''        const auto ex_save_path = starfox::app::starfox_ex_save_ram_path();
'''

addition = '''        starfox::localization::DialogueCatalog ptbr_dialogues;

        {
            const auto localization_executable =
                std::filesystem::absolute(argv[0]).parent_path();

            const auto localization_current =
                std::filesystem::current_path();

            const auto localization_workspace =
                localization_executable
                    .parent_path()
                    .parent_path();

            const std::array localization_candidates{
                localization_executable
                    / "localization"
                    / "pt_BR"
                    / "dialogue.tsv",

                localization_current
                    / "localization"
                    / "pt_BR"
                    / "dialogue.tsv",

                localization_workspace
                    / "localization"
                    / "pt_BR"
                    / "dialogue.tsv",
            };

            for (const auto& candidate :
                 localization_candidates) {

                if (!std::filesystem::exists(candidate)) {
                    continue;
                }

                if (ptbr_dialogues.load(candidate)) {
                    std::cerr
                        << "PT-BR dialogue catalog: "
                        << candidate
                        << " ("
                        << ptbr_dialogues.size()
                        << " translations)\\n";

                    break;
                }

                std::cerr
                    << "warning: invalid PT-BR dialogue catalog: "
                    << candidate
                    << '\\n';
            }
        }

        const auto log_missing_ptbr_dialogues =
            std::getenv(
                "STARFOX_LOG_MISSING_TRANSLATIONS")
            != nullptr;

        std::unordered_set<std::uint32_t>
            missing_ptbr_dialogues;

        const auto ex_save_path = starfox::app::starfox_ex_save_ram_path();
'''

replace_once(
    anchor,
    addition,
    "carregar catalogo PT-BR"
)


# ------------------------------------------------------------
# renderização das falas
# ------------------------------------------------------------

old = '''                if (dialogue.text_visible) {
                    const auto text_y = dialogue.three_lines ? 153 : 169;
                    text_renderer.draw_game_text(dialogue.text_address,
                        83, text_y + 1, comms_hud, 7U * 16U, 9U, 175);
                    text_renderer.draw_game_text(dialogue.text_address,
                        82, text_y, comms_hud, 7U * 16U, std::nullopt, 174);
                }
'''

new = '''                if (dialogue.text_visible) {
                    const auto text_y =
                        dialogue.three_lines
                        ? 153
                        : 169;

                    const auto use_ptbr =
                        game.language()
                            == starfox::localization::Language::portuguese_br;

                    const auto translated =
                        use_ptbr
                        ? ptbr_dialogues.find(
                            dialogue.text_address)
                        : std::nullopt;

                    if (translated) {
                        const auto source_colour =
                            static_cast<std::uint8_t>(
                                rom.read8(
                                    dialogue.text_address)
                                & 0x0fU);

                        const auto maximum_lines =
                            dialogue.three_lines
                            ? std::size_t{3U}
                            : std::size_t{2U};

                        text_renderer.draw_utf8_wrapped(
                            *translated,
                            83,
                            text_y + 1,
                            comms_hud,
                            9U,
                            7U * 16U,
                            175,
                            maximum_lines);

                        text_renderer.draw_utf8_wrapped(
                            *translated,
                            82,
                            text_y,
                            comms_hud,
                            source_colour,
                            7U * 16U,
                            174,
                            maximum_lines);

                    } else {
                        if (use_ptbr
                            && log_missing_ptbr_dialogues
                            && dialogue.text_address != 0U
                            && missing_ptbr_dialogues
                                .insert(
                                    dialogue.text_address)
                                .second) {

                            std::cerr
                                << "PT-BR missing dialogue: 0x"
                                << std::hex
                                << std::uppercase
                                << dialogue.text_address
                                << std::nouppercase
                                << std::dec
                                << '\\n';
                        }

                        text_renderer.draw_game_text(
                            dialogue.text_address,
                            83,
                            text_y + 1,
                            comms_hud,
                            7U * 16U,
                            9U,
                            175);

                        text_renderer.draw_game_text(
                            dialogue.text_address,
                            82,
                            text_y,
                            comms_hud,
                            7U * 16U,
                            std::nullopt,
                            174);
                    }
                }
'''

replace_once(
    old,
    new,
    "interceptar dialogos PT-BR"
)

path.write_text(
    text,
    encoding="utf-8"
)
PY

# ============================================================
# ETAPA 8 — validação
# ============================================================

section "ETAPA 8 — VALIDACAO"

python3 <<'PY'
from pathlib import Path

files = [
    "include/starfox/localization/dialogue_catalog.hpp",
    "src/localization/dialogue_catalog.cpp",
    "localization/pt_BR/dialogue.tsv",
    "tests/dialogue_catalog_tests.cpp",
    "include/starfox/render/scaled_text_renderer.hpp",
    "src/render/scaled_text_renderer.cpp",
    "src/app/starfox_pc.cpp",
    "CMakeLists.txt",
]

for filename in files:
    path = Path(filename)

    path.read_text(
        encoding="utf-8"
    )

    print(
        f"UTF8 OK  {filename}"
    )
PY

echo
echo "git diff --check..."

git diff --check

echo
echo "Diff:"

git diff --stat

# ============================================================
# ETAPA 9 — reconfigurar
# ============================================================

section "ETAPA 9 — CMAKE"

cmake \
    -S "$PROJECT_ROOT" \
    -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_EMBED_RUNTIME_ASSETS=OFF

# ============================================================
# ETAPA 10 — build
# ============================================================

section "ETAPA 10 — BUILD"

cmake \
    --build "$BUILD_DIR" \
    -j"$(nproc)"

# ============================================================
# ETAPA 11 — testes
# ============================================================

section "ETAPA 11 — CTEST"

ctest \
    --test-dir "$BUILD_DIR" \
    --output-on-failure

# ============================================================
# ETAPA 12 — smoke PT-BR
# ============================================================

section "ETAPA 12 — SMOKE PT-BR"

env \
    SDL_VIDEODRIVER=dummy \
    SDL_AUDIODRIVER=dummy \
    STARFOX_TEST_EXPERIENCE=ORIGINAL \
    STARFOX_TEST_LANGUAGE=PT_BR \
    STARFOX_TEST_FRAMES=12 \
    STARFOX_TEST_UNPACED=1 \
    "$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    BOOT

# ============================================================
# Resultado
# ============================================================

section "PT-BR FASE 03 CONCLUIDA"

echo "Infraestrutura de dialogos instalada."
echo
echo "Catalogo:"
echo "  localization/pt_BR/dialogue.tsv"
echo
echo "Comportamento:"
echo "  traducao encontrada -> PT-BR"
echo "  traducao ausente    -> ingles original"
echo
echo "Diagnostico de enderecos ausentes:"
echo
echo "  STARFOX_LOG_MISSING_TRANSLATIONS=1 \\"
echo "  $BUILD_DIR/starfox_pc \\"
echo "    upstream-ultrastarfox/SF.SFC \\"
echo "    upstream-ultrastarfox/SYMBOLS.TXT \\"
echo "    BOOT"

FINAL_RC=0

exit 0
