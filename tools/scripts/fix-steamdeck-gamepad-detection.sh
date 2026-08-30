#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD="$PROJECT_ROOT/build/linux-controller-checkpoint"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/steamdeck-input-fix/$STAMP"

mkdir -p "$REPORT_DIR/backup"

trap '
STATUS=$?
echo
echo "============================================================"
echo "SCRIPT INTERROMPIDO"
echo "============================================================"
echo "Código de saída: $STATUS"
echo "Linha aproximada: $LINENO"
echo
echo "O terminal continuará aberto."
exit $STATUS
' ERR

echo "============================================================"
echo "STAR FOX ENHANCED"
echo "FIX — STEAM DECK GAMEPAD DETECTION"
echo "============================================================"
echo

SOURCE="src/app/runtime_input.cpp"

cp -a \
    "$SOURCE" \
    "$REPORT_DIR/backup/runtime_input.cpp"

echo "[1/7] Aplicando detecção robusta..."

python3 <<'PY'
from pathlib import Path

path = Path("src/app/runtime_input.cpp")

text = path.read_text(
    encoding="utf-8"
)

start = text.find(
    "std::string gamepad_device_label(SDL_Gamepad* gamepad)"
)

end = text.find(
    "\nInputBindings::InputBindings()",
    start
)

if start < 0 or end < 0:
    raise RuntimeError(
        "gamepad_device_label() não encontrada"
    )

current = text[start:end]

marker = "STARFOX_STEAM_DECK_VID_PID_FALLBACK"

if marker in current:
    print(
        "JA OK   correção já aplicada"
    )

else:
    replacement = r'''std::string gamepad_device_label(SDL_Gamepad* gamepad) {
    if (gamepad == nullptr) {
        return "NO GAMEPAD";
    }

    // STARFOX_STEAM_DECK_VID_PID_FALLBACK
    //
    // SDL may expose virtual/native Steam Deck controllers with a
    // generic gamepad name depending on the backend and SDL version.
    // Prefer semantic names when available, but also recognize the
    // Valve Steam Deck USB VID/PID used by the actual device and by
    // our virtual-controller regression test.

    const auto* raw_name =
        SDL_GetGamepadName(
            gamepad);

    const auto name =
        raw_name == nullptr
        ? std::string_view{}
        : std::string_view{
            raw_name};


    auto* joystick =
        SDL_GetGamepadJoystick(
            gamepad);


    const auto* raw_joystick_name =
        joystick == nullptr
        ? nullptr
        : SDL_GetJoystickName(
            joystick);


    const auto joystick_name =
        raw_joystick_name == nullptr
        ? std::string_view{}
        : std::string_view{
            raw_joystick_name};


    const auto vendor =
        SDL_GetGamepadVendor(
            gamepad);

    const auto product =
        SDL_GetGamepadProduct(
            gamepad);


    constexpr std::uint16_t
        valve_vendor_id =
            0x28deU;

    constexpr std::uint16_t
        steam_deck_product_id =
            0x1205U;


    const auto is_steam_deck =
        contains(
            name,
            "steam deck")

        || contains(
            joystick_name,
            "steam deck")

        || (
            vendor
                == valve_vendor_id

            && product
                == steam_deck_product_id
        );


    if (is_steam_deck) {
        return "STEAM DECK";
    }


    if (contains(
            name,
            "steam virtual")

        || contains(
            joystick_name,
            "steam virtual")) {

        return "STEAM INPUT";
    }


    const auto type =
        SDL_GetGamepadType(
            gamepad);


    if (type
            == SDL_GAMEPAD_TYPE_XBOX360

        || type
            == SDL_GAMEPAD_TYPE_XBOXONE

        || contains(
            name,
            "xinput")

        || contains(
            joystick_name,
            "xinput")) {

        return "XINPUT / XBOX";
    }


    auto result =
        !name.empty()
        ? std::string{name}

        : !joystick_name.empty()
        ? std::string{
            joystick_name}

        : std::string{
            "GAMEPAD"};


    std::transform(
        result.begin(),
        result.end(),
        result.begin(),

        [](unsigned char character) {

            return static_cast<char>(
                std::toupper(
                    character));
        });


    if (result.size() > 20U) {
        result.resize(
            20U);
    }


    return result;
}
'''

    text = (
        text[:start]
        + replacement
        + text[end:]
    )

    path.write_text(
        text,
        encoding="utf-8"
    )

    print(
        "PATCH   gamepad_device_label()"
    )

    print(
        "        nome SDL"
    )

    print(
        "        + nome joystick"
    )

    print(
        "        + Steam Deck VID/PID"
    )
PY


echo
echo "============================================================"
echo "[2/7] VALIDAÇÃO DO PATCH"
echo "============================================================"

git diff --check

grep -n \
    -A80 \
    'STARFOX_STEAM_DECK_VID_PID_FALLBACK' \
    src/app/runtime_input.cpp \
    | head -n 100


echo
echo "============================================================"
echo "[3/7] REBUILD DO TESTE DE INPUT"
echo "============================================================"

cmake \
    --build "$BUILD" \
    --target starfox_runtime_input_tests \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-runtime-input.log"


echo
echo "============================================================"
echo "[4/7] TESTE ISOLADO"
echo "============================================================"

ctest \
    --test-dir "$BUILD" \
    -R '^starfox_runtime_input_tests$' \
    --output-on-failure \
    -VV \
    2>&1 \
    | tee "$REPORT_DIR/runtime-input-test.log"


echo
echo "============================================================"
echo "[5/7] SUÍTE COMPLETA"
echo "============================================================"

ctest \
    --test-dir "$BUILD" \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-full.log"


echo
echo "============================================================"
echo "[6/7] CONFIRMANDO 20/20"
echo "============================================================"

if grep -q \
    "100% tests passed" \
    "$REPORT_DIR/ctest-full.log"
then
    echo
    echo "SUCESSO:"
    echo "  20/20 testes passaram."
else
    echo
    echo "ERRO:"
    echo "A suíte não informou 100%."
    echo "Nenhum commit será criado."
    exit 40
fi


echo
echo "============================================================"
echo "[7/7] RETOMANDO CHECKPOINT"
echo "============================================================"

CHECKPOINT_SCRIPT="
$PROJECT_ROOT/tools/scripts/commit-switch-60fps-dualsense-checkpoint.sh
"

CHECKPOINT_SCRIPT="$(
    echo "$CHECKPOINT_SCRIPT" \
    | tr -d '\n'
)"


if [[ ! -x "$CHECKPOINT_SCRIPT" ]]
then
    echo
    echo "AVISO:"
    echo "O script de checkpoint não foi encontrado/executável."
    echo
    echo "Os 20 testes passaram, mas nenhum commit foi criado."
    echo
    echo "Esperado:"
    echo "  $CHECKPOINT_SCRIPT"
    exit 0
fi


echo
echo "Todos os testes passaram."
echo "Executando checkpoint completo..."
echo


bash "$CHECKPOINT_SCRIPT"


echo
echo "============================================================"
echo "FIX + CHECKPOINT FINALIZADOS"
echo "============================================================"
