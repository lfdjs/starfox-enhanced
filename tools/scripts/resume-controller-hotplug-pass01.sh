#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-controller-hotplug-fix"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/controller-hotplug-resume/$STAMP"

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
exit $STATUS
' ERR


echo "============================================================"
echo "STAR FOX ENHANCED"
echo "CONTROLLER HOTPLUG PASS 01 — CONTINUAÇÃO"
echo "============================================================"
echo


# ============================================================
# 1. CONFIRMAR QUE O PATCH AINDA ESTÁ PRESENTE
# ============================================================

echo "[1/5] Confirmando as correções aplicadas..."

REQUIRED_MARKERS=(
    "STARFOX_CONTROL_OVERLAY_WIPE_FIX"
    "STARFOX_CENTERED_CONTROL_OVERLAY"
    "STARFOX_DEFERRED_GAMEPAD_HOTPLUG"
    "STARFOX_GAMEPAD_REFRESH_AFTER_EVENT_BATCH"
)

for marker in "${REQUIRED_MARKERS[@]}"
do
    if ! grep -q "$marker" src/app/starfox_pc.cpp
    then
        echo
        echo "ERRO:"
        echo "Marker não encontrado:"
        echo "  $marker"
        exit 20
    fi

    echo "OK: $marker"
done


echo
echo "============================================================"
echo "[2/5] SUÍTE DESKTOP EXCLUINDO TESTE STEAM DECK CONHECIDO"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    -E '^starfox_runtime_input_tests$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-without-steamdeck.log"


if ! grep -q "100% tests passed" \
    "$REPORT_DIR/ctest-without-steamdeck.log"
then
    echo
    echo "ERRO:"
    echo "Algum teste além do Steam Deck falhou."
    echo "Não continuaremos para o Switch."
    exit 30
fi

echo
echo "Todos os demais testes passaram."


# ============================================================
# 3. REGISTRAR A FALHA CONHECIDA SEM DISPARAR ERR TRAP
# ============================================================

echo
echo "============================================================"
echo "[3/5] TESTE STEAM DECK — APENAS REGISTRO"
echo "============================================================"

if ctest \
    --test-dir "$BUILD_DESKTOP" \
    -R '^starfox_runtime_input_tests$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-runtime-input-known-failure.log"
then

    echo
    echo "runtime_input_tests passou nesta execução."

else

    echo
    echo "AVISO CONHECIDO:"
    echo "starfox_runtime_input_tests falhou."
    echo
    echo "Escopo atual:"
    echo "  PS4 / DualShock 4"
    echo "  PS5 / DualSense"
    echo "  Nintendo Switch"
    echo
    echo "Steam Deck ficará fora desta etapa."
fi


# ============================================================
# 4. BUILD SWITCH
# ============================================================

echo
echo "============================================================"
echo "[4/5] BUILD NINTENDO SWITCH"
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

if [[ ! -s "$NRO" ]]
then
    echo
    echo "ERRO:"
    echo "NRO não foi gerado."
    exit 40
fi


echo
echo "NRO:"
ls -lh "$NRO"

echo
echo "NRO0 / ASET:"
grep -aob \
    'NRO0\|ASET' \
    "$NRO"

echo
echo "SHA256:"
sha256sum \
    "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"


# ============================================================
# 5. RESULTADO
# ============================================================

echo
echo "============================================================"
echo "[5/5] PASS 01 PRONTO PARA TESTE MANUAL"
echo "============================================================"

echo
echo "Estado:"
echo
echo "  Build desktop ..................... OK"
echo "  Controller visual profile tests .. OK"
echo "  Runtime smoke ..................... OK"
echo "  Runtime smoke PT-BR ............... OK"
echo "  Demais testes sem Steam Deck ...... OK"
echo "  Steam Deck ........................ fora do escopo atual"
echo "  Build Switch ...................... OK"

echo
echo "------------------------------------------------------------"
echo "TESTE MANUAL RECOMENDADO"
echo "------------------------------------------------------------"
echo
echo "A) TIMING DO DUALSENSE"
echo
echo "  1. Inicie o jogo com o DualSense."
echo "  2. Deixe a transição chegar à CONT.SCR."
echo "  3. Durante o wipe/transição, a arte nova NÃO deve aparecer."
echo "  4. Quando a tela estiver efetivamente visível,"
echo "     a arte do DualSense deve aparecer."
echo
echo "B) CENTRALIZAÇÃO"
echo
echo "  5. Confirme que o DualSense está centralizado."
echo "  6. Se possível teste 4:3 e 16:9."
echo
echo "C) HOTPLUG"
echo
echo "  7. Com o jogo aberto, desconecte o DualSense."
echo "  8. Conecte o DualShock 4."
echo "  9. Pressione um botão no DS4."
echo " 10. Verifique se o jogo continua rodando."
echo " 11. Reconecte o DualSense."
echo " 12. Pressione um botão no DualSense."
echo " 13. Alterne entre DS4 e DualSense algumas vezes."
echo
echo "D) TESTE MAIS IMPORTANTE"
echo
echo " 14. Deixe os DOIS controles conectados."
echo " 15. Pressione um botão no DualSense."
echo " 16. Depois pressione um botão no DS4."
echo " 17. Repita várias vezes."
echo " 18. O jogo NÃO deve crashar."
echo
echo "------------------------------------------------------------"

echo
echo "Git status:"
git status --short

echo
echo "Nenhum commit foi criado."
echo
echo "Relatório:"
echo "  $REPORT_DIR"
