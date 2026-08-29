#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"
BUILD_DIR="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-argc-zero-fix/$STAMP"

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
# 1. Isolar completamente original_assets no Switch.
#
# A versão anterior retornava os assets Switch cedo, mas ainda
# compilava no mesmo lambda a lógica desktop baseada em argc /
# argv[0]. Vamos tornar os dois caminhos mutuamente exclusivos.
# ============================================================

old = '''            return switch_assets;

#endif

            if (argc == 1 || argc == 2) {
'''

new = '''            return switch_assets;

#else

            if (argc == 1 || argc == 2) {
'''

if old in text:
    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   original_assets: Switch/Desktop separados"
    )

elif new in text:
    print(
        "JA OK   original_assets já possui #else"
    )

else:
    print(
        "AVISO   ponto #endif após switch_assets não encontrado"
    )


old = '''            throw std::runtime_error{"invalid command-line arguments"};
        }();
        std::optional<RuntimeAssets> starfox_ex_assets;
'''

new = '''            throw std::runtime_error{"invalid command-line arguments"};

#endif
        }();

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] Original asset resolver complete\\n");
#endif

        std::optional<RuntimeAssets> starfox_ex_assets;
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "Fim do original_assets lambda não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   fecha caminho desktop de original_assets"
    )

else:
    print(
        "JA OK   fechamento original_assets"
    )


# ============================================================
# 2. Star Fox EX.
#
# No Switch ainda não temos o pacote EX. Mais importante:
# a descoberta desktop usa argv[0], porém argc=0 no libnx.
#
# Portanto o Switch simplesmente deixa o optional vazio.
# ============================================================

old = '''        std::optional<RuntimeAssets> starfox_ex_assets;
#if defined(_WIN32) && defined(STARFOX_HAS_EMBEDDED_ASSETS)
'''

new = '''        std::optional<RuntimeAssets> starfox_ex_assets;

#if defined(STARFOX_SWITCH_RUNTIME)

        switch_runtime_debug(
            "[SFE SWITCH] Star Fox EX external asset scan skipped\\n");

#elif defined(_WIN32) && defined(STARFOX_HAS_EMBEDDED_ASSETS)
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "Bloco starfox_ex_assets não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   evita argv[0] no carregamento EX"
    )

else:
    print(
        "JA OK   carregamento EX protegido"
    )


# ============================================================
# 3. Catálogo PT-BR.
#
# Desktop:
#     continua usando caminhos relativos ao executável.
#
# Switch:
#     usa explicitamente sdmc:.
#
# Futuramente esta parte poderá apontar para romfs:/ quando
# empacotarmos localization dentro do NRO.
# ============================================================

start_marker = (
    '        starfox::localization::'
    'DialogueCatalog ptbr_dialogues;\n'
)

end_marker = (
    '\n        const auto log_missing_ptbr_dialogues ='
)

start = text.find(start_marker)

if start < 0:
    raise RuntimeError(
        "Declaração ptbr_dialogues não encontrada"
    )

end = text.find(
    end_marker,
    start
)

if end < 0:
    raise RuntimeError(
        "Fim do bloco de localização não encontrado"
    )

segment = text[start:end]

if '#if defined(STARFOX_SWITCH_RUNTIME)' not in segment:

    declaration = start_marker

    desktop_body = segment[
        len(declaration):
    ]

    switch_body = r'''
#if defined(STARFOX_SWITCH_RUNTIME)

        {
            const std::filesystem::path candidate{
                "sdmc:/switch/starfox-enhanced/"
                "localization/pt_BR/dialogue.tsv"};

            switch_runtime_debug(
                "[SFE SWITCH] checking optional PT-BR catalog\n");

            std::ifstream probe{
                candidate};

            if (probe) {
                probe.close();

                switch_runtime_debug(
                    "[SFE SWITCH] PT-BR catalog accessible\n");

                if (ptbr_dialogues.load(candidate)) {

                    std::string message{
                        "[SFE SWITCH] PT-BR catalog loaded: "};

                    message += std::to_string(
                        ptbr_dialogues.size());

                    message += " translations\n";

                    switch_runtime_debug(
                        message);

                } else {

                    switch_runtime_debug(
                        "[SFE SWITCH] WARNING: PT-BR catalog invalid\n");
                }

            } else {

                // Localization is optional during the Switch bootstrap.
                // English ROM text remains the fallback.
                switch_runtime_debug(
                    "[SFE SWITCH] PT-BR catalog not installed; "
                    "continuing with ROM text\n");
            }
        }

#else
'''

    replacement = (
        declaration
        + switch_body
        + desktop_body
        + '\n#endif\n'
    )

    text = (
        text[:start]
        + replacement
        + text[end:]
    )

    print(
        "PATCH   localização Switch não usa argv[0]"
    )

else:
    print(
        "JA OK   localização Switch já protegida"
    )


# ============================================================
# 4. Checkpoint depois de todos os assets auxiliares
# ============================================================

old = '''        const auto log_missing_ptbr_dialogues =
'''

new = '''#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] auxiliary asset discovery complete\\n");

        switch_runtime_debug(
            "[SFE SWITCH] before runtime settings setup\\n");
#endif

        const auto log_missing_ptbr_dialogues =
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "log_missing_ptbr_dialogues não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   checkpoint assets auxiliares"
    )

else:
    print(
        "JA OK   checkpoint assets auxiliares"
    )


# ============================================================
# 5. Evitar persistência EX durante bootstrap Switch.
#
# O jogo inicia na experiência Original e não temos EX instalado.
# Não há motivo para consultar save EX neste estágio.
# ============================================================

old = '''        const auto persist_ex_save =
            std::getenv("STARFOX_TEST_FRAMES") == nullptr
            && std::getenv("STARFOX_TEST_EXPERIENCE") == nullptr
            && std::getenv("STARFOX_TEST_PRESSES") == nullptr;
'''

new = '''#if defined(STARFOX_SWITCH_RUNTIME)
        const auto persist_ex_save = false;
#else
        const auto persist_ex_save =
            std::getenv("STARFOX_TEST_FRAMES") == nullptr
            && std::getenv("STARFOX_TEST_EXPERIENCE") == nullptr
            && std::getenv("STARFOX_TEST_PRESSES") == nullptr;
#endif
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "persist_ex_save não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   persistência EX desabilitada no bootstrap Switch"
    )

else:
    print(
        "JA OK   persistência EX Switch"
    )


# ============================================================
# 6. Checkpoint antes da construção efetiva do jogo.
# ============================================================

old = '''        const auto& assets = active_experience
                == starfox::simulation::Experience::starfox_ex
            ? *starfox_ex_assets : original_assets;
        const auto& rom = assets.rom;
        const auto& symbols = assets.symbols;
        const starfox::assets::ShapeDecoder decoder{rom, symbols};
        const auto trigonometry = starfox::simulation::TrigTables::load(rom, symbols);
'''

new = '''#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] entering runtime construction\\n");
#endif

        const auto& assets = active_experience
                == starfox::simulation::Experience::starfox_ex
            ? *starfox_ex_assets : original_assets;

        const auto& rom = assets.rom;
        const auto& symbols = assets.symbols;

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] before ShapeDecoder\\n");
#endif

        const starfox::assets::ShapeDecoder decoder{
            rom,
            symbols};

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] ShapeDecoder OK\\n");

        switch_runtime_debug(
            "[SFE SWITCH] before TrigTables::load\\n");
#endif

        const auto trigonometry =
            starfox::simulation::TrigTables::load(
                rom,
                symbols);

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] TrigTables::load OK\\n");
#endif
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "Construção ShapeDecoder/TrigTables não encontrada"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   checkpoints ShapeDecoder/TrigTables"
    )

else:
    print(
        "JA OK   checkpoints ShapeDecoder/TrigTables"
    )


# ============================================================
# 7. GameSimulation
# ============================================================

old = '''        starfox::simulation::GameSimulation game{
            rom, symbols, initial_map, initial_ex_save};
'''

new = '''#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] before GameSimulation constructor\\n");
#endif

        starfox::simulation::GameSimulation game{
            rom,
            symbols,
            initial_map,
            initial_ex_save};

#if defined(STARFOX_SWITCH_RUNTIME)
        switch_runtime_debug(
            "[SFE SWITCH] GameSimulation constructor OK\\n");
#endif
'''

if new not in text:

    if old not in text:
        raise RuntimeError(
            "GameSimulation constructor não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   checkpoints GameSimulation"
    )

else:
    print(
        "JA OK   checkpoints GameSimulation"
    )


path.write_text(
    text,
    encoding="utf-8"
)

print()
print(
    "Correção argc=0 aplicada."
)
PY

echo
echo "============================================================"
echo "VALIDAÇÃO"
echo "============================================================"

git diff --check

echo
echo "Ocorrências restantes de argv[0]:"
echo

grep -n \
    'argv\[0\]' \
    src/app/starfox_pc.cpp \
    || true

echo
echo "Observação:"
echo "As ocorrências restantes devem pertencer apenas aos caminhos"
echo "Windows/Desktop protegidos por pré-processador."
echo

echo "============================================================"
echo "TRECHO STAR FOX EX"
echo "============================================================"

grep -n \
    -A35 \
    -B8 \
    'Star Fox EX external asset scan skipped' \
    src/app/starfox_pc.cpp \
    || true

echo
echo "============================================================"
echo "TRECHO LOCALIZAÇÃO"
echo "============================================================"

grep -n \
    -A50 \
    -B5 \
    'checking optional PT-BR catalog' \
    src/app/starfox_pc.cpp \
    || true

echo
echo "============================================================"
echo "BUILD SWITCH"
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
echo "NRO CHECK"
echo "============================================================"

ls -lh "$NRO"

grep -aob \
    'NRO0\|ASET' \
    "$NRO"

sha256sum \
    "$NRO" \
    | tee "$REPORT_DIR/sha256.txt"

{
    echo "STAR FOX ENHANCED — SWITCH argc=0 FIX"
    echo
    echo "Diagnóstico:"
    echo "  libnx/Ryubing fornece argc=0."
    echo "  caminhos Switch agora não usam argv[0]."
    echo
    echo "NRO:"
    echo "  $NRO"
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
