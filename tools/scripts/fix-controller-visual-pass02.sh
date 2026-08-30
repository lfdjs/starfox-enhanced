#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"
BUILD="$PROJECT_ROOT/build/linux-controller-pass02"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/controller-visual-pass02/$STAMP"

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
echo "CONTROLLER VISUAL + HOTPLUG — PASS 02"
echo "============================================================"
echo


# ============================================================
# 1. BACKUP
# ============================================================

echo "[1/7] Criando backup..."

cp -a \
    "$SOURCE" \
    "$REPORT_DIR/backup/starfox_pc.cpp"


# ============================================================
# 2. PATCH
# ============================================================

echo
echo "============================================================"
echo "[2/7] Aplicando correções"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

path = Path("src/app/starfox_pc.cpp")

text = path.read_text(
    encoding="utf-8"
)


# ============================================================
# A. POSIÇÃO DO DUALSENSE
# ============================================================

old = '''            const auto overlay_x =
                (static_cast<float>(width) - overlay_width)
                * 0.5F;
'''

new = '''            // STARFOX_DUALSENSE_PANEL_CENTER_PASS02
            //
            // The controller belongs visually to CONT.SCR's left flight
            // panel, not to the centre of the complete widescreen canvas.
            //
            // Cartridge coordinates:
            //   flight window = x 24 .. 136
            //   centre        = x 80
            //
            // The QOI crop contains transparent horizontal space, so the
            // visible DualSense centre sits approximately 48 pixels from the
            // destination origin. Anchor that visible centre to x=80 and
            // then apply the widescreen viewport origin.

            constexpr float cartridge_width =
                256.0F;

            constexpr float controls_window_centre_x =
                80.0F;

            constexpr float dualsense_visible_centre_in_crop =
                48.0F;

            const auto cartridge_viewport_origin =
                width > static_cast<std::uint32_t>(
                    cartridge_width)

                ? (
                    static_cast<float>(width)
                    - cartridge_width
                  ) * 0.5F

                : 0.0F;

            const auto overlay_x =
                cartridge_viewport_origin
                + controls_window_centre_x
                - dualsense_visible_centre_in_crop;
'''

if "STARFOX_DUALSENSE_PANEL_CENTER_PASS02" not in text:

    if old not in text:
        raise RuntimeError(
            "Não encontrei a fórmula de centralização do Pass01."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   DualSense centralizado no painel CONT.SCR"
    )

else:

    print(
        "JA OK   centralização Pass02"
    )


# ============================================================
# B. CONTADOR DE ESTABILIZAÇÃO DA TELA
# ============================================================

old = '''        bool suppress_fullscreen_start{};
        double last_phase_fraction{};
'''

new = '''        bool suppress_fullscreen_start{};
        double last_phase_fraction{};

        // STARFOX_CONTROL_SCREEN_STABLE_COUNTER
        //
        // GameFlowState switches to CONT.SCR before every visual transition
        // affecting that screen has necessarily completed. Delay only the
        // host replacement artwork, never cartridge logic.
        std::uint32_t control_screen_stable_frames{};
'''

if "STARFOX_CONTROL_SCREEN_STABLE_COUNTER" not in text:

    if old not in text:
        raise RuntimeError(
            "Não encontrei o estado principal de apresentação."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   contador de estabilidade CONT.SCR"
    )

else:

    print(
        "JA OK   contador de estabilidade"
    )


# ============================================================
# C. DEFINIR QUANDO A ARTE CUSTOMIZADA PODE APARECER
# ============================================================

old = '''            const auto controls_screen = game.flow_state()
                    == starfox::simulation::GameFlowState::controls_type
                || game.flow_state()
                    == starfox::simulation::GameFlowState::controls_choice;
'''

new = '''            const auto controls_screen = game.flow_state()
                    == starfox::simulation::GameFlowState::controls_type
                || game.flow_state()
                    == starfox::simulation::GameFlowState::controls_choice;

            // STARFOX_CONTROL_SCREEN_READY_PASS02
            //
            // Do not let host artwork race the cartridge transition.
            const auto controls_wipe_active =
                game.window_wipe_state().active;

            if (controls_screen
                && !controls_wipe_active) {

                control_screen_stable_frames =
                    std::min<std::uint32_t>(
                        control_screen_stable_frames + 1U,
                        255U);

            } else {

                control_screen_stable_frames =
                    0U;
            }

            constexpr std::uint32_t
                required_control_screen_stable_frames =
                    3U;

            const auto control_screen_ready =
                controls_screen
                && !controls_wipe_active
                && control_screen_stable_frames
                    >= required_control_screen_stable_frames;


            // For now the custom visual system is intentionally restricted
            // to the PlayStation controllers currently being implemented.
            //
            // Keyboard input remains fully functional, but it does NOT cause
            // an artwork/profile transition yet. If no supported controller
            // is active, CONT.SCR keeps its original cartridge artwork.
            const auto detected_control_profile =
                gamepad != nullptr

                ? starfox::app::detect_control_visual_profile(
                    gamepad)

                : starfox::app::ControlVisualProfile::
                    keyboard_pc;


            const auto playstation_control_visual =
                gamepad != nullptr
                && (
                    detected_control_profile
                        == starfox::app::
                            ControlVisualProfile::
                                dualshock4

                    || detected_control_profile
                        == starfox::app::
                            ControlVisualProfile::
                                dualsense
                );


            const auto custom_control_visual_ready =
                control_screen_ready
                && playstation_control_visual;
'''

if "STARFOX_CONTROL_SCREEN_READY_PASS02" not in text:

    if old not in text:
        raise RuntimeError(
            "Não encontrei controls_screen."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   host overlay só entra após CONT.SCR estabilizar"
    )

else:

    print(
        "JA OK   gating CONT.SCR"
    )


# ============================================================
# D. NÃO MUDAR ARTE PARA TECLADO
# ============================================================

old = '''            // Draw last on CONT.SCR so the replacement also covers the
            // original controller's high-priority BG and OBJ callouts.
            if (controls_screen) {
                starfox::app::draw_control_visual_profile(
                    starfox::app::detect_control_visual_profile(
                        keyboard_control_active ? nullptr : gamepad),
                    framebuffer, text_renderer, viewport_origin, ppu.cgram);
            }
'''

new = '''            // STARFOX_PLAYSTATION_VISUAL_ONLY_PASS02
            //
            // Draw only after CONT.SCR is genuinely visible. Keyboard input
            // does not participate in visual-profile switching yet.
            if (custom_control_visual_ready) {

                starfox::app::draw_control_visual_profile(
                    detected_control_profile,
                    framebuffer,
                    text_renderer,
                    viewport_origin,
                    ppu.cgram);
            }
'''

if "STARFOX_PLAYSTATION_VISUAL_ONLY_PASS02" not in text:

    if old not in text:
        raise RuntimeError(
            "Não encontrei o draw_control_visual_profile atual."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   teclado removido do switching visual"
    )

else:

    print(
        "JA OK   switching visual restrito a PlayStation"
    )


# ============================================================
# E. OVERLAY HD USA EXATAMENTE A MESMA REGRA
# ============================================================

old = '''            presentation_effects.high_res_control_overlay = controls_screen
                && starfox::app::detect_control_visual_profile(
                    keyboard_control_active ? nullptr : gamepad)
                    == starfox::app::ControlVisualProfile::dualsense;
'''

new = '''            // STARFOX_HD_CONTROL_READY_PASS02
            presentation_effects.high_res_control_overlay =
                custom_control_visual_ready
                && detected_control_profile
                    == starfox::app::
                        ControlVisualProfile::
                            dualsense;
'''

if "STARFOX_HD_CONTROL_READY_PASS02" not in text:

    if old not in text:
        raise RuntimeError(
            "Não encontrei high_res_control_overlay."
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   DualSense HD usa gating estabilizado"
    )

else:

    print(
        "JA OK   HD overlay gating"
    )


path.write_text(
    text,
    encoding="utf-8"
)

print()
print(
    "Pass02 aplicado com sucesso."
)
PY


# ============================================================
# 3. VALIDAR
# ============================================================

echo
echo "============================================================"
echo "[3/7] Validando diff"
echo "============================================================"

git diff --check

grep -n \
    'STARFOX_DUALSENSE_PANEL_CENTER_PASS02\|STARFOX_CONTROL_SCREEN_STABLE_COUNTER\|STARFOX_CONTROL_SCREEN_READY_PASS02\|STARFOX_PLAYSTATION_VISUAL_ONLY_PASS02\|STARFOX_HD_CONTROL_READY_PASS02' \
    src/app/starfox_pc.cpp

echo
echo "Resumo:"
git diff --stat


# ============================================================
# 4. BUILD EXATO QUE SERÁ EXECUTADO
# ============================================================

echo
echo "============================================================"
echo "[4/7] Build desktop RelWithDebInfo"
echo "============================================================"

cmake \
    -S . \
    -B "$BUILD" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_BUILD_SWITCH=OFF

cmake \
    --build "$BUILD" \
    --target starfox_pc \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-starfox-pc.log"

BIN="$BUILD/starfox_pc"

test -x "$BIN"

echo
echo "Executável desta validação:"
echo "  $BIN"

echo
echo "Timestamp:"
stat \
    --format='  %y  %s bytes' \
    "$BIN"

echo
echo "SHA256:"
sha256sum "$BIN" \
    | tee "$REPORT_DIR/starfox-pc-sha256.txt"


# ============================================================
# 5. TESTES RELACIONADOS
# ============================================================

echo
echo "============================================================"
echo "[5/7] Testes relacionados"
echo "============================================================"

cmake \
    --build "$BUILD" \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-all.log"

ctest \
    --test-dir "$BUILD" \
    -R 'starfox_control_visual_profile_tests|starfox_runtime_smoke$|starfox_runtime_smoke_ptbr$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-related.log"


# ============================================================
# 6. DEMAIS TESTES, EXCLUINDO O TESTE FORA DO ESCOPO
# ============================================================

echo
echo "============================================================"
echo "[6/7] Suíte sem runtime_input_tests"
echo "============================================================"

ctest \
    --test-dir "$BUILD" \
    -E '^starfox_runtime_input_tests$' \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest-no-runtime-input.log"


# ============================================================
# 7. EXECUTAR EXATAMENTE ESTE BINÁRIO
# ============================================================

echo
echo "============================================================"
echo "[7/7] TESTE MANUAL"
echo "============================================================"
echo
echo "IMPORTANTE:"
echo
echo "O jogo que abrir agora é EXATAMENTE:"
echo "  $BIN"
echo
echo "Teste nesta ordem:"
echo
echo "  1. Aguarde a CONT.SCR aparecer completamente."
echo "  2. Confira a posição do DualSense."
echo "  3. Pressione algumas teclas do teclado."
echo "  4. O jogo deve continuar funcionando."
echo "  5. A arte NÃO deve trocar para teclado."
echo "  6. Volte a usar o DualSense."
echo "  7. Se tiver DS4 disponível, alterne DS4 <-> DualSense."
echo "  8. Desconecte e reconecte um controle."
echo "  9. Feche normalmente o jogo."
echo

ulimit -c unlimited || true

set +e

(
    cd "$PROJECT_ROOT"

    "$BIN"
) 2>&1 | tee "$REPORT_DIR/runtime.log"

GAME_STATUS=${PIPESTATUS[0]}

set -e


echo
echo "============================================================"
echo "RESULTADO DA EXECUÇÃO"
echo "============================================================"

echo
echo "Exit code:"
echo "  $GAME_STATUS"


if [[ "$GAME_STATUS" -ne 0 ]]
then

    echo
    echo "O runtime terminou de forma anormal."

    if command -v coredumpctl >/dev/null 2>&1
    then
        echo
        echo "Último coredump relacionado ao starfox_pc:"
        echo

        coredumpctl \
            --no-pager \
            info \
            "$BIN" \
            2>/dev/null \
            | tail -n 120 \
            | tee "$REPORT_DIR/coredump-info.txt" \
            || true
    fi

else

    echo
    echo "Runtime encerrado normalmente."
fi


echo
echo "============================================================"
echo "PASS02 FINALIZADO"
echo "============================================================"

echo
echo "Nenhum commit foi criado."

echo
echo "Relatório:"
echo "  $REPORT_DIR"

echo
echo "Git status:"
git status --short
