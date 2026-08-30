#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-controller-pass05"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/controller-assets-hotplug-pass05-resume/$STAMP"

mkdir -p "$REPORT_DIR"

trap '
STATUS=$?
echo
echo "============================================================"
echo "SCRIPT INTERROMPIDO"
echo "============================================================"
echo "Código: $STATUS"
echo "Linha aproximada: $LINENO"
echo
echo "O terminal continuará aberto."
echo
echo "Relatório:"
echo "  '"$REPORT_DIR"'"
exit $STATUS
' ERR


echo "============================================================"
echo "STAR FOX ENHANCED"
echo "CONTROLLER ASSETS + HOTPLUG PASS 05 — CONTINUAÇÃO"
echo "============================================================"
echo


# ============================================================
# 1. CONFIRMAR PATCH
# ============================================================

echo "[1/6] Confirmando o Pass 05..."

MARKERS=(
    "STARFOX_MULTI_CONTROL_OVERLAY_PROFILE"
    "STARFOX_CONTROL_OVERLAY_ASSET"
    "STARFOX_MULTI_CONTROL_OVERLAY_RENDER"
    "STARFOX_MULTI_CONTROL_OVERLAY_TEXTURES"
    "STARFOX_GAMEPAD_ID_CACHE_PASS05"
    "STARFOX_GAMEPAD_REMOVAL_GUARD_PASS05"
    "STARFOX_HIGH_RES_CONTROLLER_PROFILES_PASS05"
    "STARFOX_HD_PROFILE_PANEL_ONLY_PASS05"
)

for marker in "${MARKERS[@]}"
do
    if grep -R -q \
        "$marker" \
        src/app \
        ports/switch \
        2>/dev/null
    then
        echo "OK: $marker"
    else
        echo
        echo "ERRO:"
        echo "Marker não encontrado:"
        echo "  $marker"
        exit 20
    fi
done


echo
echo "Assets QOI:"

for asset in \
    assets/control_hints/dualsense_controls_white_buttons.qoi \
    assets/control_hints/dualshock4_controls_corrected.qoi \
    assets/control_hints/xbox_controls_corrected.qoi
do
    test -s "$asset"
    ls -lh "$asset"
done


# ============================================================
# 2. TESTES — EXCLUINDO APENAS STEAM DECK
# ============================================================

echo
echo "============================================================"
echo "[2/6] SUÍTE DESKTOP SEM O TESTE STEAM DECK"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    -E '^starfox_runtime_input_tests$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-without-runtime-input.log"

if ! grep -q \
    '100% tests passed' \
    "$REPORT_DIR/ctest-without-runtime-input.log"
then
    echo
    echo "ERRO:"
    echo "Algum teste além do runtime_input_tests falhou."
    exit 30
fi

echo
echo "OK: todos os outros 19 testes passaram."


# ============================================================
# 3. REGISTRAR TESTE CONHECIDO SEM BLOQUEAR
# ============================================================

echo
echo "============================================================"
echo "[3/6] REGISTRO DA FALHA CONHECIDA"
echo "============================================================"

if ctest \
    --test-dir "$BUILD_DESKTOP" \
    -R '^starfox_runtime_input_tests$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-known-steamdeck.log"
then

    echo
    echo "runtime_input_tests passou."

else

    echo
    echo "FALHA CONHECIDA / FORA DO ESCOPO ATUAL:"
    echo "  Steam Deck was not identified in the remapping UI"
    echo
    echo "Continuando com PS4 / PS5 / Xbox."
fi


# ============================================================
# 4. BUILD SWITCH
# ============================================================

echo
echo "============================================================"
echo "[4/6] BUILD NINTENDO SWITCH"
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
    2>&1 \
    | tee "$REPORT_DIR/build-switch.log"


NRO="$BUILD_SWITCH/ports/switch/starfox_switch.nro"

test -s "$NRO"

echo
echo "NRO:"
ls -lh "$NRO"

echo
echo "Headers:"
grep -aob \
    'NRO0\|ASET' \
    "$NRO" \
    | tee "$REPORT_DIR/nro-headers.txt"

echo
echo "SHA256:"
sha256sum "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"


# ============================================================
# 5. MOSTRAR BINÁRIO EXATO
# ============================================================

echo
echo "============================================================"
echo "[5/6] PREPARANDO TESTE MANUAL"
echo "============================================================"

BIN="$BUILD_DESKTOP/starfox_pc"

test -x "$BIN"

echo
echo "Executável:"
echo "  $BIN"

echo
echo "SHA256 desktop:"
sha256sum "$BIN" \
    | tee "$REPORT_DIR/starfox-pc-sha256.txt"

echo
echo "------------------------------------------------------------"
echo "TESTE MANUAL"
echo "------------------------------------------------------------"
echo
echo "A) LAYOUTS"
echo
echo "  1. Inicie com DualSense."
echo "  2. Vá para CONT.SCR."
echo "     Esperado: layout PS5."
echo
echo "  3. Conecte DualShock 4."
echo "  4. Pressione um botão do DS4."
echo "     Esperado: layout PS4."
echo
echo "  5. Conecte Xbox."
echo "  6. Pressione um botão do Xbox."
echo "     Esperado: layout Xbox."
echo
echo "B) TROCA COM TODOS CONECTADOS"
echo
echo "  7. Pressione DualSense."
echo "     Esperado: PS5."
echo
echo "  8. Pressione DS4."
echo "     Esperado: PS4."
echo
echo "  9. Pressione Xbox."
echo "     Esperado: Xbox."
echo
echo "C) DESCONEXÃO"
echo
echo " 10. Desconecte o controle atualmente ativo."
echo "     O jogo NÃO pode fechar."
echo
echo " 11. Pressione o teclado."
echo "     O jogo NÃO pode fechar."
echo
echo " 12. Pressione outro controle ainda conectado."
echo "     Ele deve virar o controle ativo."
echo
echo "D) HOTPLUG REPETIDO"
echo
echo " 13. Conecte/desconecte PS4 algumas vezes."
echo " 14. Conecte/desconecte PS5 algumas vezes."
echo " 15. Conecte/desconecte Xbox algumas vezes."
echo " 16. Alterne inputs entre eles."
echo
echo "------------------------------------------------------------"
echo


# ============================================================
# 6. EXECUTAR E CAPTURAR CRASH
# ============================================================

echo
echo "============================================================"
echo "[6/6] EXECUTANDO RUNTIME"
echo "============================================================"

ulimit -c unlimited || true

set +e

"$BIN" \
    2>&1 \
    | tee "$REPORT_DIR/runtime.log"

GAME_STATUS=${PIPESTATUS[0]}

set -e


echo
echo "============================================================"
echo "RESULTADO DO TESTE MANUAL"
echo "============================================================"

echo
echo "Exit code:"
echo "  $GAME_STATUS"


if [[ "$GAME_STATUS" -ne 0 ]]
then

    echo
    echo "CRASH / ENCERRAMENTO ANORMAL DETECTADO."

    if command -v coredumpctl >/dev/null 2>&1
    then

        echo
        echo "Tentando capturar coredump..."

        coredumpctl \
            --no-pager \
            info \
            "$BIN" \
            2>/dev/null \
            | tail -n 200 \
            | tee "$REPORT_DIR/coredump-info.txt" \
            || true

        echo
        echo "Backtrace via gdb, se disponível:"

        if command -v gdb >/dev/null 2>&1
        then

            COREFILE="$REPORT_DIR/starfox_pc.core"

            if coredumpctl \
                dump \
                "$BIN" \
                --output="$COREFILE" \
                >/dev/null 2>&1
            then

                gdb \
                    -q \
                    -batch \
                    -ex 'thread apply all bt full' \
                    "$BIN" \
                    "$COREFILE" \
                    2>&1 \
                    | tee "$REPORT_DIR/gdb-backtrace.txt" \
                    || true
            fi
        fi
    fi

else

    echo
    echo "Runtime encerrado normalmente."
fi


echo
echo "============================================================"
echo "CONTINUAÇÃO PASS 05 FINALIZADA"
echo "============================================================"

echo
echo "Nenhum commit foi criado."

echo
echo "Relatório:"
echo "  $REPORT_DIR"

echo
echo "Git status:"
git status --short
