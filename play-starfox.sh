#!/usr/bin/env bash

set -Eeuo pipefail

MAP="${1:-BOOT}"

PROJECT_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
    pwd
)"

ROM_PATH="$PROJECT_ROOT/upstream-ultrastarfox/SF.SFC"
SYMBOLS_PATH="$PROJECT_ROOT/upstream-ultrastarfox/SYMBOLS.TXT"

EX_ROM_PATH="$PROJECT_ROOT/upstream-star-fox-ex/SFES/SFES.SFC"
EX_SYMBOLS_PATH="$PROJECT_ROOT/upstream-star-fox-ex/SYMBOLS.TXT"

BUILD_PATH="$PROJECT_ROOT/build/linux-release"
EXECUTABLE_PATH="$BUILD_PATH/starfox_pc"

echo
echo "============================================================"
echo "STAR FOX ENHANCED — LINUX"
echo "============================================================"
echo
echo "Projeto:"
echo "  $PROJECT_ROOT"
echo
echo "Mapa:"
echo "  $MAP"
echo

if [[ ! -s "$ROM_PATH" ]]; then
    echo "ERRO: UltraStarFox SF.SFC não encontrado:"
    echo "$ROM_PATH"
    exit 10
fi

if [[ ! -s "$SYMBOLS_PATH" ]]; then
    echo "ERRO: UltraStarFox SYMBOLS.TXT não encontrado:"
    echo "$SYMBOLS_PATH"
    exit 11
fi

if [[ -s "$EX_ROM_PATH" && -s "$EX_SYMBOLS_PATH" ]]; then
    echo "Star Fox EX assets: OK"
else
    echo "AVISO:"
    echo "Os assets do Star Fox EX não estão completos."
    echo "A experiência Original continua disponível."
fi

if [[ ! -x "$EXECUTABLE_PATH" ]]; then

    echo
    echo "Executável Linux ainda não existe."
    echo "Configurando e compilando..."
    echo

    cmake \
        -S "$PROJECT_ROOT" \
        -B "$BUILD_PATH" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DSTARFOX_BUILD_RUNTIME=ON \
        -DSTARFOX_BUILD_TESTS=ON \
        -DSTARFOX_EMBED_RUNTIME_ASSETS=OFF

    cmake \
        --build "$BUILD_PATH" \
        --target starfox_pc \
        -j"$(nproc)"
fi

echo
echo "============================================================"
echo "INICIANDO STAR FOX ENHANCED"
echo "============================================================"
echo

cd "$PROJECT_ROOT"

exec \
    "$EXECUTABLE_PATH" \
    "$ROM_PATH" \
    "$SYMBOLS_PATH" \
    "$MAP"

