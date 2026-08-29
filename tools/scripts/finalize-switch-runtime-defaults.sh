#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_DIR="$PROJECT_ROOT/build-switch"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-runtime-defaults/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED"
echo "NINTENDO SWITCH — FINALIZAÇÃO DO BOOTSTRAP"
echo "============================================================"

echo
echo "Verificando Git..."
echo

git fetch origin main

LOCAL_HEAD="$(git rev-parse HEAD)"
REMOTE_HEAD="$(git rev-parse origin/main)"

echo "Local : $LOCAL_HEAD"
echo "Remote: $REMOTE_HEAD"

if ! git merge-base --is-ancestor "$REMOTE_HEAD" "$LOCAL_HEAD"
then
    if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]]
    then
        echo
        echo "ERRO:"
        echo "origin/main contém commits que não existem neste working tree."
        echo "Interrompendo para não sobrescrever alterações remotas."
        exit 30
    fi
fi

FILES=(
    include/starfox/app/platform_profile.hpp
    src/app/starfox_pc.cpp
    src/app/runtime_input.cpp
    ports/switch/README.md
)

for file in "${FILES[@]}"
do
    if [[ ! -f "$file" ]]
    then
        echo "ERRO: $file não encontrado."
        exit 10
    fi

    mkdir -p \
        "$REPORT_DIR/backup/$(dirname "$file")"

    cp -a \
        "$file" \
        "$REPORT_DIR/backup/$file"
done

export PROJECT_ROOT

python3 <<'PY'
from pathlib import Path
import os

root = Path(os.environ["PROJECT_ROOT"])

# ============================================================
# 1. PERFIL SWITCH
#
# BOOT:
#     sequência completa do jogo, incluindo Nintendo Presents.
#
# unlocked_20_fps:
#     lógica determinística fixa em 20 Hz.
#
# presentation_fps:
#     apresentação em 60 FPS.
#
# widescreen_16_9:
#     perfil padrão/fixo do port Switch.
# ============================================================

path = root / "include/starfox/app/platform_profile.hpp"
text = path.read_text(encoding="utf-8")

old = '''[[nodiscard]] constexpr RuntimePlatformProfile switch_runtime_profile() {
    return {
        "TITLEMAP",
        simulation::TimingMode::unlocked_20_fps,
        60U,
        simulation::DisplayMode::standard_4_3,
        true,
        false,
    };
}
'''

new = '''[[nodiscard]] constexpr RuntimePlatformProfile switch_runtime_profile() {
    return {
        "BOOT",
        simulation::TimingMode::unlocked_20_fps,
        60U,
        simulation::DisplayMode::widescreen_16_9,
        true,
        false,
    };
}
'''

if new in text:
    print("JA OK   perfil Switch")

elif old in text:
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print("PATCH   Switch: BOOT / 20 Hz / 60 FPS / 16:9")

else:
    raise RuntimeError(
        "switch_runtime_profile() não corresponde ao formato esperado"
    )


# ============================================================
# 2. TRAVAR EXPERIÊNCIA ORIGINAL NO SWITCH
#
# Desktop mantém:
#     arquivo de preferências
#     STARFOX_TEST_EXPERIENCE
#
# Switch:
#     sempre Original nesta fase do port.
# ============================================================

path = root / "src/app/starfox_pc.cpp"
text = path.read_text(encoding="utf-8")

marker = (
    "[SFE SWITCH] runtime profile: "
    "ORIGINAL / 20HZ / 60FPS / 16:9 / ENGLISH"
)

if marker not in text:

    start_text = '''        auto active_experience = static_cast<starfox::simulation::Experience>(
            saved_pregame.experience);
'''

    start = text.find(start_text)

    if start < 0:
        raise RuntimeError(
            "active_experience não encontrado"
        )

    end_text = '''        bool restart_runtime = true;
'''

    end = text.find(end_text, start)

    if end < 0:
        raise RuntimeError(
            "fim da configuração active_experience não encontrado"
        )

    desktop_block = text[start:end]

    switch_block = '''#if defined(STARFOX_SWITCH_RUNTIME)

        auto active_experience =
            starfox::simulation::Experience::original;

        switch_runtime_debug(
            "[SFE SWITCH] runtime profile: "
            "ORIGINAL / 20HZ / 60FPS / 16:9 / ENGLISH\\\\n");

#else

''' + desktop_block + '''#endif

'''

    text = (
        text[:start]
        + switch_block
        + text[end:]
    )

    print("PATCH   experiência Original travada no Switch")

else:
    print("JA OK   experiência Original Switch")


# ============================================================
# 3. IDIOMA INGLÊS EXPLÍCITO
# ============================================================

old = '''            if (platform_profile.bypass_host_pregame_menu) {
                starfox::app::apply_runtime_platform_profile(
                    game, platform_profile);
            }
'''

new = '''            if (platform_profile.bypass_host_pregame_menu) {
                starfox::app::apply_runtime_platform_profile(
                    game, platform_profile);
            }

#if defined(STARFOX_SWITCH_RUNTIME)
            // Switch currently ships with the Original experience and
            // English text as fixed production defaults. PT-BR remains in
            // development and is intentionally not selected automatically.
            game.set_experience(
                starfox::simulation::Experience::original);

            game.set_language(
                starfox::localization::Language::english);
#endif
'''

if new in text:
    print("JA OK   idioma/experiência Switch")

elif old in text:
    text = text.replace(old, new, 1)
    print("PATCH   idioma inglês explícito")

else:
    raise RuntimeError(
        "apply_runtime_platform_profile não encontrado"
    )

path.write_text(text, encoding="utf-8")


# ============================================================
# 4. INPUT NATIVO LIBNX
#
# SDL continua sendo utilizado normalmente.
#
# Este caminho funciona como fallback nativo:
#
# Switch B      -> SNES B
# Switch Y      -> SNES Y
# Minus         -> SELECT
# Plus          -> START
# D-pad/stick   -> D-pad SNES
# Switch A      -> SNES A
# Switch X      -> SNES X
# L/R           -> L/R
#
# Isto remove a dependência exclusiva do mapeamento SDL para
# passar pela tela PUSH START.
# ============================================================

path = root / "src/app/runtime_input.cpp"
text = path.read_text(encoding="utf-8")

include_anchor = '''#include <vector>
'''

include_new = '''#include <vector>

#if defined(STARFOX_SWITCH_RUNTIME)
#include <switch.h>
#endif
'''

if include_new not in text:

    if include_anchor not in text:
        raise RuntimeError(
            "include <vector> não encontrado"
        )

    text = text.replace(
        include_anchor,
        include_new,
        1
    )

    print("PATCH   include libnx")
else:
    print("JA OK   include libnx")


helper_marker = "sample_switch_native_buttons()"

if helper_marker not in text:

    anchor = '''constexpr std::int16_t kAxisThreshold = 16'000;
'''

    helper = r'''constexpr std::int16_t kAxisThreshold = 16'000;

#if defined(STARFOX_SWITCH_RUNTIME)

input::ButtonMask sample_switch_native_buttons() noexcept {
    static PadState pad{};
    static bool initialized{};

    if (!initialized) {
        padConfigureInput(
            1,
            HidNpadStyleSet_NpadStandard);

        padInitializeDefault(
            &pad);

        initialized = true;
    }

    padUpdate(
        &pad);

    const auto held =
        padGetButtons(
            &pad);

    input::ButtonMask result{};

    const auto add =
        [&result, held](
            u64 physical,
            input::ButtonMask logical) {

            if ((held & physical) != 0U) {
                result =
                    static_cast<input::ButtonMask>(
                        result | logical);
            }
        };

    // Preserve the physical SNES-style diamond layout.
    add(HidNpadButton_B, input::b);
    add(HidNpadButton_Y, input::y);

    add(HidNpadButton_Minus, input::select);
    add(HidNpadButton_Plus, input::start);

    add(HidNpadButton_Up, input::up);
    add(HidNpadButton_Down, input::down);
    add(HidNpadButton_Left, input::left);
    add(HidNpadButton_Right, input::right);

    add(HidNpadButton_A, input::a);
    add(HidNpadButton_X, input::x);

    add(HidNpadButton_L, input::left_shoulder);
    add(HidNpadButton_R, input::right_shoulder);

    // Star Fox also accepts the left analogue stick as D-pad input.
    const auto stick =
        padGetStickPos(
            &pad,
            0);

    constexpr int threshold =
        16'000;

    if (stick.y >= threshold) {
        result =
            static_cast<input::ButtonMask>(
                result | input::up);
    }

    if (stick.y <= -threshold) {
        result =
            static_cast<input::ButtonMask>(
                result | input::down);
    }

    if (stick.x <= -threshold) {
        result =
            static_cast<input::ButtonMask>(
                result | input::left);
    }

    if (stick.x >= threshold) {
        result =
            static_cast<input::ButtonMask>(
                result | input::right);
    }

    return result;
}

#endif
'''

    if anchor not in text:
        raise RuntimeError(
            "kAxisThreshold não encontrado"
        )

    text = text.replace(
        anchor,
        helper,
        1
    )

    print("PATCH   input nativo libnx")
else:
    print("JA OK   input nativo libnx")


# ============================================================
# 5. InputBindings::sample
# ============================================================

old = '''input::ButtonMask InputBindings::sample(SDL_Gamepad* gamepad) const noexcept {
    const auto* keys = SDL_GetKeyboardState(nullptr);
    input::ButtonMask result{};
    for (std::size_t action = 0; action < action_count; ++action) {
        add_keyboard_button(
            result, keys, keyboard_[action], kActionButtons[action]);
    }
    return static_cast<input::ButtonMask>(
        result | sample_gamepad_only(gamepad));
}
'''

new = '''input::ButtonMask InputBindings::sample(SDL_Gamepad* gamepad) const noexcept {
#if defined(STARFOX_SWITCH_RUNTIME)

    // libnx is the authoritative console input source. Keep SDL gamepad
    // sampling ORed in as a compatibility path for emulators and future
    // SDL backend improvements.
    auto result =
        sample_switch_native_buttons();

#else

    const auto* keys =
        SDL_GetKeyboardState(nullptr);

    input::ButtonMask result{};

    for (std::size_t action = 0;
         action < action_count;
         ++action) {

        add_keyboard_button(
            result,
            keys,
            keyboard_[action],
            kActionButtons[action]);
    }

#endif

    return static_cast<input::ButtonMask>(
        result
        | sample_gamepad_only(gamepad));
}
'''

if new in text:
    print("JA OK   InputBindings::sample")

elif old in text:
    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   InputBindings::sample usa libnx")

else:
    raise RuntimeError(
        "InputBindings::sample não encontrado"
    )


# ============================================================
# 6. Navegação fixa de menu
# ============================================================

old = '''input::ButtonMask InputBindings::sample_fixed_menu_navigation(
    SDL_Gamepad* gamepad) const noexcept {
    const auto* keys = SDL_GetKeyboardState(nullptr);
    input::ButtonMask result{};
    add_keyboard_button(result, keys, SDL_SCANCODE_UP, input::up);
    add_keyboard_button(result, keys, SDL_SCANCODE_DOWN, input::down);
    add_keyboard_button(result, keys, SDL_SCANCODE_LEFT, input::left);
    add_keyboard_button(result, keys, SDL_SCANCODE_RIGHT, input::right);
    add_keyboard_button(result, keys, SDL_SCANCODE_X, input::a);
    add_keyboard_button(result, keys, SDL_SCANCODE_A, input::y);
    add_keyboard_button(result, keys, SDL_SCANCODE_Z, input::b);
    add_keyboard_button(result, keys, SDL_SCANCODE_RETURN, input::start);
'''

new = '''input::ButtonMask InputBindings::sample_fixed_menu_navigation(
    SDL_Gamepad* gamepad) const noexcept {

#if defined(STARFOX_SWITCH_RUNTIME)

    auto result =
        sample_switch_native_buttons();

#else

    const auto* keys =
        SDL_GetKeyboardState(nullptr);

    input::ButtonMask result{};

    add_keyboard_button(result, keys, SDL_SCANCODE_UP, input::up);
    add_keyboard_button(result, keys, SDL_SCANCODE_DOWN, input::down);
    add_keyboard_button(result, keys, SDL_SCANCODE_LEFT, input::left);
    add_keyboard_button(result, keys, SDL_SCANCODE_RIGHT, input::right);
    add_keyboard_button(result, keys, SDL_SCANCODE_X, input::a);
    add_keyboard_button(result, keys, SDL_SCANCODE_A, input::y);
    add_keyboard_button(result, keys, SDL_SCANCODE_Z, input::b);
    add_keyboard_button(result, keys, SDL_SCANCODE_RETURN, input::start);

#endif
'''

if new in text:
    print("JA OK   menu input Switch")

elif old in text:
    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   navegação de menu usa libnx")

else:
    raise RuntimeError(
        "sample_fixed_menu_navigation não encontrado"
    )

path.write_text(
    text,
    encoding="utf-8"
)


# ============================================================
# 7. README SWITCH
# ============================================================

path = root / "ports/switch/README.md"
text = path.read_text(encoding="utf-8")

old = '''The Switch profile always:

- presents at 60 FPS in handheld and docked modes;
- advances gameplay at the original deterministic 20 Hz logic frequency;
- starts at the cartridge title (`TITLEMAP`) instead of the host configuration
  screen;
- ignores the desktop pregame settings file; and
- uses a fullscreen 1280x720 SDL surface, which the system scales for the
  active display mode.
'''

new = '''The Switch profile always:

- presents at 60 FPS in handheld and docked modes;
- advances gameplay at the deterministic 20 Hz logic frequency;
- starts from the cartridge boot sequence (`BOOT`), including the original
  Nintendo Presents sequence before the title screen;
- uses the Original experience;
- defaults to the 16:9 widescreen renderer;
- uses English as the production language while PT-BR remains incomplete;
- ignores the desktop pregame settings file; and
- uses a fullscreen 1280x720 SDL surface, which the system scales for the
  active display mode.
'''

if new in text:
    print("JA OK   README defaults")

elif old in text:
    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   README defaults Switch")

else:
    print(
        "AVISO   seção de defaults do README mudou; "
        "não foi substituída automaticamente"
    )


old = '''The runtime presently uses SDL's unified gamepad mapping. Dynamic controller
art for single Joy-Con, paired Joy-Con, handheld, and Pro Controller is a
separate follow-up milestone; it requires libnx controller-style detection
and new original artwork.
'''

new = '''The runtime uses SDL's unified gamepad mapping together with a libnx-native
Player 1 fallback. The native path maps Plus directly to SNES Start, Minus to
Select, the Switch face-button diamond to the equivalent SNES buttons, and
accepts both D-pad and left stick movement. This keeps console input independent
from emulator-specific SDL mapping while remaining compatible with real Switch
hardware.

Dynamic controller art for single Joy-Con, paired Joy-Con, handheld, and Pro
Controller remains a separate follow-up milestone.
'''

if new in text:
    print("JA OK   README input")

elif old in text:
    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   README input Switch")

path.write_text(
    text,
    encoding="utf-8"
)

print()
print("Ajustes Switch aplicados.")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO DE CÓDIGO"
echo "============================================================"

git diff --check

echo
echo "Perfil Switch:"
grep -n \
    -A12 \
    'switch_runtime_profile' \
    include/starfox/app/platform_profile.hpp \
    | head -n 15

echo
echo "Input libnx:"
grep -n \
    -A12 \
    'sample_switch_native_buttons' \
    src/app/runtime_input.cpp \
    | head -n 30

echo
echo "Defaults runtime:"
grep -n \
    'runtime profile: ORIGINAL' \
    src/app/starfox_pc.cpp \
    || true

echo
echo "============================================================"
echo "BUILD SWITCH"
echo "============================================================"

export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"

"$DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake" \
    -S . \
    -B "$BUILD_DIR" \
    -DSTARFOX_BUILD_RUNTIME=OFF \
    -DSTARFOX_BUILD_TESTS=OFF \
    -DSTARFOX_BUILD_SWITCH=ON \
    -DCMAKE_BUILD_TYPE=Release

cmake \
    --build "$BUILD_DIR" \
    --target starfox_switch_nro \
    -j"$(nproc)" \
    --verbose \
    2>&1 \
    | tee "$REPORT_DIR/build-switch.log"

NRO="$BUILD_DIR/ports/switch/starfox_switch.nro"

echo
echo "============================================================"
echo "VALIDAÇÃO NRO"
echo "============================================================"

test -s "$NRO"

ls -lh "$NRO"

grep -aob \
    'NRO0\|ASET' \
    "$NRO"

sha256sum \
    "$NRO" \
    | tee "$REPORT_DIR/nro-sha256.txt"

echo
echo "============================================================"
echo "TESTES DESKTOP — SE BUILD EXISTIR"
echo "============================================================"

if [[ -d "$PROJECT_ROOT/build/linux-ptbr-phase1" ]]
then
    cmake \
        --build "$PROJECT_ROOT/build/linux-ptbr-phase1" \
        -j"$(nproc)"

    ctest \
        --test-dir "$PROJECT_ROOT/build/linux-ptbr-phase1" \
        --output-on-failure
else
    echo "Build desktop não encontrado; teste desktop ignorado."
fi

echo
echo "============================================================"
echo "PREPARANDO COMMIT"
echo "============================================================"

git add -A

# Não versionar logs de build eventualmente criados na raiz.
git restore \
    --staged \
    -- build-switch-nro.log \
    2>/dev/null \
    || true

# Nunca incluir ROMs comerciais em um commit por acidente.
while IFS= read -r file
do
    [[ -z "$file" ]] && continue

    echo "REMOVENDO ROM DO STAGING: $file"

    git restore \
        --staged \
        -- "$file" \
        2>/dev/null \
        || true

done < <(
    git diff \
        --cached \
        --name-only \
    | grep -Ei '\.(sfc|smc|fig|swc|rom)$' \
    || true
)

# Também não incluir cópias soltas dos assets runtime.
for file in \
    SF.SFC \
    SFES.SFC \
    SYMBOLS.TXT \
    SFES-SYMBOLS.TXT
do
    git restore \
        --staged \
        -- "$file" \
        2>/dev/null \
        || true
done

echo
echo "Arquivos que entrarão no commit:"
echo

git diff \
    --cached \
    --name-status

echo
echo "Resumo:"
git diff \
    --cached \
    --stat

if git diff \
    --cached \
    --quiet
then
    echo
    echo "Nenhuma alteração para commit."
    exit 40
fi

echo
echo "============================================================"
echo "COMMIT"
echo "============================================================"

git commit \
    -s \
    -m "Advance Nintendo Switch runtime bring-up"

COMMIT_SHA="$(git rev-parse HEAD)"

echo
echo "Commit criado:"
echo "  $COMMIT_SHA"

echo
echo "============================================================"
echo "PUSH"
echo "============================================================"

git push \
    origin \
    HEAD:main

echo
echo "============================================================"
echo "CONCLUÍDO"
echo "============================================================"

echo
echo "Switch runtime:"
echo "  Boot       : BOOT / Nintendo Presents"
echo "  Experience : Original"
echo "  Logic      : 20 Hz"
echo "  Video      : 60 FPS"
echo "  Display    : 16:9 widescreen"
echo "  Language   : English"
echo "  Start      : Switch Plus -> SNES Start"
echo "  Select     : Switch Minus -> SNES Select"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "Commit:"
echo "  $COMMIT_SHA"
echo
echo "Remote:"
git log \
    -1 \
    --oneline \
    --decorate
echo
echo "Status final:"
git status --short

{
    echo "STAR FOX ENHANCED — SWITCH RUNTIME DEFAULTS"
    echo
    echo "Commit:"
    echo "  $COMMIT_SHA"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "NRO SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "Git:"
    git log -1 --oneline --decorate
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
