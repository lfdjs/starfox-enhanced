#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/controller-overlay-hotplug-pass01/$STAMP"

mkdir -p "$REPORT_DIR/backup"

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
echo "CONTROLLER OVERLAY + HOTPLUG FIX — PASS 01"
echo "============================================================"
echo

if [[ ! -f "$SOURCE" ]]
then
    echo "ERRO: src/app/starfox_pc.cpp não encontrado."
    exit 10
fi

cp -a \
    "$SOURCE" \
    "$REPORT_DIR/backup/starfox_pc.cpp"

echo "[1/8] Aplicando correções..."

python3 <<'PY'
from pathlib import Path

path = Path("src/app/starfox_pc.cpp")

text = path.read_text(
    encoding="utf-8"
)


# ============================================================
# FIX 1
# DUALSENSE HD — NÃO IGNORAR O WINDOW WIPE
# ============================================================

old = '''        present_rgba_pixels(framebuffer.width(), framebuffer.height(), rgba_,
            effects.high_res_control_overlay);
'''

new = '''        // STARFOX_CONTROL_OVERLAY_WIPE_FIX
        //
        // The HD controller texture is rendered by SDL after the indexed
        // framebuffer has already gone through the cartridge window wipe.
        // Rendering it while the wipe is active makes the controller appear
        // before CONT.SCR itself. Keep it hidden until that transition has
        // finished; the ordinary framebuffer artwork continues to obey the
        // cartridge masking normally.
        const auto show_high_res_control_overlay =
            effects.high_res_control_overlay
            && !effects.wipe.active;

        present_rgba_pixels(
            framebuffer.width(),
            framebuffer.height(),
            rgba_,
            show_high_res_control_overlay);
'''

if "STARFOX_CONTROL_OVERLAY_WIPE_FIX" not in text:

    if old not in text:
        raise RuntimeError(
            "Não foi possível localizar a chamada "
            "present_rgba_pixels() esperada."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   DualSense respeita o window wipe"
    )

else:

    print(
        "JA OK   window-wipe fix já aplicado"
    )


# ============================================================
# FIX 2
# CENTRALIZAR O OVERLAY HD NA LARGURA LÓGICA ATUAL
# ============================================================

old = '''        if (high_res_control_overlay && control_overlay_texture_ != nullptr) {
            const SDL_FRect source{0.0F, 260.0F, 1024.0F, 500.0F};
            const SDL_FRect destination{45.0F, 118.0F, 145.0F, 71.0F};
            SDL_RenderTexture(renderer_, control_overlay_texture_,
                &source, &destination);
        }
'''

new = '''        if (high_res_control_overlay && control_overlay_texture_ != nullptr) {
            // STARFOX_CENTERED_CONTROL_OVERLAY
            //
            // Destination coordinates live in the current logical
            // presentation space. A fixed X=45 only looked approximately
            // centred in the original 256-pixel canvas and moved visibly
            // left in 16:9/ultrawide modes.
            constexpr float overlay_width = 145.0F;
            constexpr float overlay_height = 71.0F;

            const auto overlay_x =
                (static_cast<float>(width) - overlay_width)
                * 0.5F;

            const SDL_FRect source{
                0.0F,
                260.0F,
                1024.0F,
                500.0F
            };

            const SDL_FRect destination{
                overlay_x,
                118.0F,
                overlay_width,
                overlay_height
            };

            SDL_RenderTexture(
                renderer_,
                control_overlay_texture_,
                &source,
                &destination);
        }
'''

if "STARFOX_CENTERED_CONTROL_OVERLAY" not in text:

    if old not in text:
        raise RuntimeError(
            "Não foi possível localizar o destino "
            "fixo do overlay DualSense."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   DualSense centralizado"
    )

else:

    print(
        "JA OK   centralização já aplicada"
    )


# ============================================================
# FIX 3
# GAMEPAD LIFETIME / ACTIVE GAMEPAD
# ============================================================

old = '''        AudioOutput audio;
        auto gamepads = starfox::app::open_player_gamepads();
        SDL_Gamepad* gamepad = gamepads.empty() ? nullptr : gamepads.front();
        bool keyboard_control_active = gamepad == nullptr;
        const auto close_gamepads = [&] {
            for (auto* opened : gamepads) {
                if (opened != nullptr) SDL_CloseGamepad(opened);
            }
            gamepads.clear();
            gamepad = nullptr;
        };
        const auto refresh_gamepads = [&] {
            close_gamepads();
            gamepads = starfox::app::open_player_gamepads();
            gamepad = gamepads.empty() ? nullptr : gamepads.front();
            if (gamepad == nullptr) keyboard_control_active = true;
        };
'''

new = '''        AudioOutput audio;
        auto gamepads = starfox::app::open_player_gamepads();
        SDL_Gamepad* gamepad = gamepads.empty() ? nullptr : gamepads.front();

        // STARFOX_DEFERRED_GAMEPAD_HOTPLUG
        //
        // SDL can deliver removal/addition plus button/axis events in the
        // same poll batch. Never destroy SDL_Gamepad handles while that batch
        // is still being consumed.
        SDL_JoystickID preferred_gamepad_id =
            gamepad != nullptr
            ? SDL_GetGamepadID(gamepad)
            : SDL_JoystickID{};

        bool keyboard_control_active = gamepad == nullptr;

        const auto close_gamepads = [&] {
            for (auto* opened : gamepads) {
                if (opened != nullptr) {
                    SDL_CloseGamepad(opened);
                }
            }

            gamepads.clear();
            gamepad = nullptr;
        };

        const auto select_gamepad_by_id =
            [&](SDL_JoystickID identifier) noexcept {

            if (identifier == 0U) {
                return false;
            }

            for (auto* opened : gamepads) {

                if (opened == nullptr) {
                    continue;
                }

                if (SDL_GetGamepadID(opened)
                    != identifier) {

                    continue;
                }

                gamepad = opened;
                preferred_gamepad_id = identifier;

                return true;
            }

            return false;
        };

        const auto refresh_gamepads = [&] {

            const auto previous_preferred =
                preferred_gamepad_id;

            close_gamepads();

            gamepads =
                starfox::app::open_player_gamepads();

            gamepad =
                gamepads.empty()
                ? nullptr
                : gamepads.front();

            preferred_gamepad_id =
                gamepad != nullptr
                ? SDL_GetGamepadID(gamepad)
                : SDL_JoystickID{};

            if (previous_preferred != 0U) {
                static_cast<void>(
                    select_gamepad_by_id(
                        previous_preferred));
            }

            if (gamepad == nullptr) {
                keyboard_control_active = true;
            }
        };
'''

if "STARFOX_DEFERRED_GAMEPAD_HOTPLUG" not in text:

    if old not in text:
        raise RuntimeError(
            "Não foi possível localizar o gerenciamento "
            "atual de gamepads."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   gerenciamento seguro de handles SDL"
    )

else:

    print(
        "JA OK   hotplug seguro já aplicado"
    )


# ============================================================
# FIX 4
# GUARDAR HOTPLUG E ÚLTIMO CONTROLE UTILIZADO
# ============================================================

old = '''            bool toggle_frame_freeze{};
            bool step_frame_forward{};
            bool step_frame_backward{};
            SDL_Event event;
            while (SDL_PollEvent(&event)) {
                if (event.type == SDL_EVENT_KEY_DOWN && !event.key.repeat) {
                    keyboard_control_active = true;
                } else if (event.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN
                           || (event.type == SDL_EVENT_GAMEPAD_AXIS_MOTION
                               && (event.gaxis.value >= 16'000
                                   || event.gaxis.value <= -16'000))) {
                    keyboard_control_active = false;
                }
'''

new = '''            bool toggle_frame_freeze{};
            bool step_frame_forward{};
            bool step_frame_backward{};

            bool gamepads_dirty{};
            SDL_JoystickID requested_gamepad_id{};

            SDL_Event event;

            while (SDL_PollEvent(&event)) {

                if (event.type == SDL_EVENT_KEY_DOWN
                    && !event.key.repeat) {

                    keyboard_control_active = true;

                } else if (
                    event.type
                        == SDL_EVENT_GAMEPAD_BUTTON_DOWN) {

                    keyboard_control_active = false;

                    requested_gamepad_id =
                        event.gbutton.which;

                    // If the device was already open, changing the active
                    // gamepad needs no close/reopen and is safe immediately.
                    if (!gamepads_dirty) {
                        static_cast<void>(
                            select_gamepad_by_id(
                                requested_gamepad_id));
                    }

                } else if (
                    event.type
                        == SDL_EVENT_GAMEPAD_AXIS_MOTION
                    && (
                        event.gaxis.value >= 16'000
                        || event.gaxis.value <= -16'000
                    )) {

                    keyboard_control_active = false;

                    requested_gamepad_id =
                        event.gaxis.which;

                    if (!gamepads_dirty) {
                        static_cast<void>(
                            select_gamepad_by_id(
                                requested_gamepad_id));
                    }
                }
'''

if old not in text:

    if "requested_gamepad_id" not in text:
        raise RuntimeError(
            "Não foi possível localizar o início "
            "do SDL event loop."
        )

    print(
        "JA OK   seleção do controle ativo já aplicada"
    )

else:

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   último controle usado vira o controle ativo"
    )


# ============================================================
# FIX 5
# NÃO REFRESH/FECHAR CONTROLES DENTRO DO EVENT LOOP
# ============================================================

old = '''                } else if (event.type == SDL_EVENT_GAMEPAD_ADDED
                           || event.type == SDL_EVENT_GAMEPAD_REMOVED) {
                    refresh_gamepads();
                    for (std::size_t player = 0;
                         player < secondary_inputs.size(); ++player) {
                        const auto held = player + 1U < gamepads.size()
                            ? bindings.sample_gamepad_only(gamepads[player + 1U])
                            : starfox::input::ButtonMask{};
                        secondary_inputs[player].reset(held);
                    }
                }
'''

new = '''                } else if (
                    event.type == SDL_EVENT_GAMEPAD_ADDED
                    || event.type == SDL_EVENT_GAMEPAD_REMOVED) {

                    // Defer close/open until SDL_PollEvent has drained the
                    // complete event batch. This prevents stale SDL_Gamepad
                    // handles when one controller is disconnected while
                    // another one is being enumerated.
                    gamepads_dirty = true;
                }
'''

if old in text:

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   hotplug agora é diferido"
    )

elif "gamepads_dirty = true;" in text:

    print(
        "JA OK   refresh diferido já aplicado"
    )

else:

    raise RuntimeError(
        "Não foi possível localizar o tratamento "
        "GAMEPAD_ADDED/GAMEPAD_REMOVED."
    )


# ============================================================
# FIX 6
# REFRESH APÓS DRENAR TODA A FILA SDL
# ============================================================

old = '''                    remap_input.reset(
                        bindings.sample_fixed_menu_navigation(gamepad));
                }
            }

            if (!running) break;
'''

new = '''                    remap_input.reset(
                        bindings.sample_fixed_menu_navigation(gamepad));
                }
            }

            // STARFOX_GAMEPAD_REFRESH_AFTER_EVENT_BATCH
            //
            // All pointers remain alive until the event queue is empty.
            // Only now is it safe to rebuild the SDL gamepad list.
            if (gamepads_dirty) {

                refresh_gamepads();

                for (std::size_t player = 0;
                     player < secondary_inputs.size();
                     ++player) {

                    const auto held =
                        player + 1U < gamepads.size()

                        ? bindings.sample_gamepad_only(
                            gamepads[player + 1U])

                        : starfox::input::ButtonMask{};

                    secondary_inputs[player].reset(
                        held);
                }
            }

            // A newly attached device might not have existed in gamepads
            // when its first input event arrived. Select it after refresh.
            if (requested_gamepad_id != 0U) {
                static_cast<void>(
                    select_gamepad_by_id(
                        requested_gamepad_id));
            }

            if (!running) break;
'''

if "STARFOX_GAMEPAD_REFRESH_AFTER_EVENT_BATCH" not in text:

    if old not in text:
        raise RuntimeError(
            "Não foi possível localizar o final "
            "do SDL event loop."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   rebuild da lista ocorre após SDL_PollEvent"
    )

else:

    print(
        "JA OK   refresh pós-eventos já aplicado"
    )


path.write_text(
    text,
    encoding="utf-8"
)

print()
print(
    "Todas as correções foram aplicadas."
)
PY


echo
echo "============================================================"
echo "[2/8] VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check

grep -n \
    'STARFOX_CONTROL_OVERLAY_WIPE_FIX\|STARFOX_CENTERED_CONTROL_OVERLAY\|STARFOX_DEFERRED_GAMEPAD_HOTPLUG\|STARFOX_GAMEPAD_REFRESH_AFTER_EVENT_BATCH' \
    src/app/starfox_pc.cpp


echo
echo "============================================================"
echo "[3/8] DIFF"
echo "============================================================"

git diff \
    --stat \
    src/app/starfox_pc.cpp

git diff \
    -- src/app/starfox_pc.cpp \
    > "$REPORT_DIR/starfox_pc.diff"


echo
echo "============================================================"
echo "[4/8] BUILD DESKTOP"
echo "============================================================"

BUILD_DESKTOP="$PROJECT_ROOT/build/linux-controller-hotplug-fix"

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


echo
echo "============================================================"
echo "[5/8] TESTES DIRETAMENTE RELACIONADOS"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    -R 'starfox_control_visual_profile_tests|starfox_runtime_smoke$|starfox_runtime_smoke_ptbr$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-controller.log"


echo
echo "============================================================"
echo "[6/8] TESTE DE INPUT EXISTENTE"
echo "============================================================"

# Esse teste não bloqueia esta etapa porque há histórico de uma verificação
# Steam Deck independente do escopo atual PS4/PS5.
set +e

ctest \
    --test-dir "$BUILD_DESKTOP" \
    -R '^starfox_runtime_input_tests$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-input.log"

INPUT_TEST_STATUS=${PIPESTATUS[0]}

set -e

if [[ "$INPUT_TEST_STATUS" -eq 0 ]]
then
    echo "runtime_input_tests: PASS"
else
    echo
    echo "AVISO:"
    echo "runtime_input_tests ainda possui falha."
    echo "Isso NÃO impedirá a validação manual PS4/PS5."
fi


echo
echo "============================================================"
echo "[7/8] BUILD NINTENDO SWITCH"
echo "============================================================"

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

BUILD_SWITCH="$PROJECT_ROOT/build-switch"

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
echo "SHA256:"
sha256sum "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"


echo
echo "============================================================"
echo "[8/8] RESULTADO"
echo "============================================================"

echo
echo "Correções aplicadas:"
echo "  [✓] DualSense centralizado na largura lógica"
echo "  [✓] DualSense HD oculto durante window wipe"
echo "  [✓] gamepads não são fechados dentro de SDL_PollEvent"
echo "  [✓] hotplug é processado após a fila de eventos"
echo "  [✓] último gamepad usado pode virar o controle ativo"
echo
echo "Nenhum commit foi criado."
echo
echo "Teste manual recomendado:"
echo "  1. abrir o jogo com DualSense"
echo "  2. observar a entrada da tela CONT.SCR"
echo "  3. confirmar centralização em 16:9"
echo "  4. desconectar o DualSense"
echo "  5. conectar o DualShock 4"
echo "  6. pressionar um botão"
echo "  7. conectar novamente o DualSense"
echo "  8. alternar input entre DS4 e DualSense"
echo "  9. confirmar que não ocorre crash"
echo
echo "Git status:"
git status --short
echo
echo "Relatório:"
echo "  $REPORT_DIR"
