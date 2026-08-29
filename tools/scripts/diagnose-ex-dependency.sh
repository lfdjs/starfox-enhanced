#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ex-dependency-diagnostics/$STAMP"

mkdir -p "$REPORT_DIR"

REPORT="$REPORT_DIR/report.txt"

{
    echo "STAR FOX ENHANCED — DIAGNÓSTICO DA DEPENDÊNCIA STAR FOX EX"
    echo
    echo "Data: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo "Projeto: $PROJECT_ROOT"

    echo
    echo "============================================================"
    echo "GIT"
    echo "============================================================"

    git status --short || true
    git log -1 --oneline || true

    echo
    echo "============================================================"
    echo "MENSAGEM DE ERRO EX"
    echo "============================================================"

    grep \
        -RnsF \
        --exclude-dir=.git \
        --exclude-dir=build \
        --exclude-dir=out \
        --exclude-dir=dist \
        --exclude-dir=upstream-ultrastarfox \
        --exclude-dir=upstream-star-fox-ex \
        'Star Fox EX runtime assets are not installed in this build' \
        . \
        || true

    echo
    echo "============================================================"
    echo "REFERÊNCIAS A STARFOX_EX"
    echo "============================================================"

    grep \
        -RnsEi \
        --exclude-dir=.git \
        --exclude-dir=build \
        --exclude-dir=out \
        --exclude-dir=dist \
        --exclude-dir=upstream-ultrastarfox \
        --exclude-dir=upstream-star-fox-ex \
        'STARFOX_EX|Star Fox EX|starfox_ex|ex_assets|EX_ROM|EX_SYMBOL' \
        src include tests CMakeLists.txt config \
        2>/dev/null \
        || true

    echo
    echo "============================================================"
    echo "CONTEXTO DA MENSAGEM DE ERRO"
    echo "============================================================"

    MATCH="$(
        grep \
            -RnsF \
            --exclude-dir=.git \
            --exclude-dir=build \
            --exclude-dir=out \
            --exclude-dir=dist \
            --exclude-dir=upstream-ultrastarfox \
            --exclude-dir=upstream-star-fox-ex \
            'Star Fox EX runtime assets are not installed in this build' \
            . \
            | head -n 1 \
            || true
    )"

    if [[ -n "$MATCH" ]]; then

        FILE="${MATCH%%:*}"

        REST="${MATCH#*:}"
        LINE="${REST%%:*}"

        START=$((LINE - 120))
        END=$((LINE + 160))

        if (( START < 1 )); then
            START=1
        fi

        echo "Arquivo: $FILE"
        echo "Linha:   $LINE"
        echo
        echo "Trecho $START-$END:"
        echo

        nl -ba "$FILE" \
            | sed -n "${START},${END}p"

    else
        echo "Mensagem literal não encontrada."
    fi

    echo
    echo "============================================================"
    echo "CMAKE — LÓGICA DE ASSETS"
    echo "============================================================"

    grep \
        -nE \
        'STARFOX_EX|STARFOX_EMBED_RUNTIME_ASSETS|STARFOX_RUNTIME_ASSETS_EMBEDDED' \
        CMakeLists.txt \
        || true

    echo
    echo "============================================================"
    echo "TESTES DE RUNTIME"
    echo "============================================================"

    grep \
        -RnsE \
        'starfox_runtime_smoke|embedded_runtime|STARFOX_TEST_EXPERIENCE' \
        CMakeLists.txt tests \
        2>/dev/null \
        || true

    echo
    echo "============================================================"
    echo "ASSETS EXISTENTES"
    echo "============================================================"

    for file in \
        upstream-ultrastarfox/SF.SFC \
        upstream-ultrastarfox/SYMBOLS.TXT \
        upstream-star-fox-ex/SFES/SFES.SFC \
        upstream-star-fox-ex/SYMBOLS.TXT
    do

        if [[ -s "$file" ]]; then
            printf 'OK      %s  %s bytes\n' \
                "$file" \
                "$(stat -c '%s' "$file")"
        else
            printf 'AUSENTE %s\n' "$file"
        fi

    done

} | tee "$REPORT"

echo
echo "Relatório:"
echo "$REPORT"
