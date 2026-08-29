#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-intro-60fps/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — NINTENDO SWITCH"
echo "BOOT DIRETO + 20 HZ + 60 FPS + 16:9"
echo "============================================================"
echo

git fetch origin main

echo "Local HEAD : $(git rev-parse --short HEAD)"
echo "origin/main: $(git rev-parse --short origin/main)"
echo

if ! git merge-base --is-ancestor origin/main HEAD
then
    echo "ERRO:"
    echo "origin/main contém alterações não presentes neste checkout."
    echo "Faça a sincronização antes de continuar."
    exit 30
fi

FILES=(
    include/starfox/app/platform_profile.hpp
    tests/platform_profile_tests.cpp
    src/app/starfox_pc.cpp
    ports/switch/README.md
)

for file in "${FILES[@]}"
do
    test -f "$file" || {
        echo "ERRO: arquivo ausente: $file"
        exit 10
    }

    mkdir -p "$REPORT_DIR/backup/$(dirname "$file")"

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
# 1. PERFIL DE PLATAFORMA
# ============================================================

path = root / "include/starfox/app/platform_profile.hpp"
text = path.read_text(encoding="utf-8")

# Adiciona a política de pacing ao perfil.
old = '''    bool bypass_host_pregame_menu{};
    bool persist_host_pregame_settings{true};
};
'''

new = '''    bool bypass_host_pregame_menu{};
    bool persist_host_pregame_settings{true};

    // Desktop disables renderer VSync and uses its precise software pacer.
    // Switch keeps EGL swap interval 1, so a second software wait would
    // throttle the same presentation twice.
    bool software_frame_pacer{true};
};
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "Campos finais de RuntimePlatformProfile não encontrados"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   RuntimePlatformProfile::software_frame_pacer")
else:
    print("JA OK   software_frame_pacer")


# Switch deve entrar diretamente no intro real da ROM.
old = '''[[nodiscard]] constexpr RuntimePlatformProfile switch_runtime_profile() {
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

new = '''[[nodiscard]] constexpr RuntimePlatformProfile switch_runtime_profile() {
    return {
        "INTROMAP",
        simulation::TimingMode::unlocked_20_fps,
        60U,
        simulation::DisplayMode::widescreen_16_9,
        true,
        false,
        false,
    };
}
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "switch_runtime_profile esperado não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   Switch BOOT -> INTROMAP")
else:
    print("JA OK   Switch INTROMAP")

path.write_text(text, encoding="utf-8")


# ============================================================
# 2. TESTE DO CONTRATO DA PLATAFORMA
# ============================================================

path = root / "tests/platform_profile_tests.cpp"
text = path.read_text(encoding="utf-8")

text = text.replace(
    '''    static_assert(desktop.persist_host_pregame_settings);
''',
    '''    static_assert(desktop.persist_host_pregame_settings);
    static_assert(desktop.software_frame_pacer);
''',
    1
) if (
    'static_assert(desktop.software_frame_pacer);'
    not in text
) else text

old = '''    static_assert(console.initial_map == "BOOT");
'''

new = '''    static_assert(console.initial_map == "INTROMAP");
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "assert de initial_map do Switch não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   teste: INTROMAP")
else:
    print("JA OK   teste INTROMAP")

anchor = '''    static_assert(console.display_mode
        == starfox::simulation::DisplayMode::widescreen_16_9);
'''

addition = '''    static_assert(console.display_mode
        == starfox::simulation::DisplayMode::widescreen_16_9);
    static_assert(!console.software_frame_pacer);
'''

if 'static_assert(!console.software_frame_pacer);' not in text:
    if anchor not in text:
        raise RuntimeError(
            "assert widescreen não encontrado"
        )

    text = text.replace(
        anchor,
        addition,
        1
    )

    print("PATCH   teste: Switch usa display VSync")
else:
    print("JA OK   teste software pacer")

path.write_text(text, encoding="utf-8")


# ============================================================
# 3. RUNTIME — REMOVER DUPLO PACING NO SWITCH
# ============================================================

path = root / "src/app/starfox_pc.cpp"
text = path.read_text(encoding="utf-8")


# ------------------------------------------------------------
# Startup preroll
# ------------------------------------------------------------

old = '''                if (!running) break;
                if (!test_unpaced) startup_pacer.wait_for_next_frame();
                window.present(framebuffer, startup_palette, {});
'''

new = '''                if (!running) break;

                // Desktop uses the software presentation clock because its
                // renderer runs with VSync disabled. Switch already blocks
                // SDL_RenderPresent on the 60 Hz EGL swap interval; sleeping
                // here as well would double-throttle presentation.
                if (!test_unpaced
                    && platform_profile.software_frame_pacer) {
                    startup_pacer.wait_for_next_frame();
                }

                window.present(
                    framebuffer,
                    startup_palette,
                    {});
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "startup PresentationPacer não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   startup: sem pacer duplo no Switch")
else:
    print("JA OK   startup pacing")


# ------------------------------------------------------------
# Main presentation loop
# ------------------------------------------------------------

old = '''            if (!test_unpaced && !advance_frozen_frame) {
                pacer.wait_for_next_frame(game.presentation_fps());
            }
'''

new = '''            if (!test_unpaced
                && !advance_frozen_frame
                && platform_profile.software_frame_pacer) {

                pacer.wait_for_next_frame(
                    game.presentation_fps());
            }
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "PresentationPacer principal não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   main loop: Switch usa somente VSync")
else:
    print("JA OK   main pacing")


# ------------------------------------------------------------
# Debug do perfil Switch
# ------------------------------------------------------------

old = '''[SFE SWITCH] runtime profile: ORIGINAL / 20HZ / 60FPS / 16:9 / ENGLISH'''

new = '''[SFE SWITCH] runtime profile: INTROMAP / ORIGINAL / 20HZ / 60FPS / 16:9 / ENGLISH / VSYNC'''

if old in text and new not in text:
    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   debug profile")
elif new in text:
    print("JA OK   debug profile")
else:
    print("AVISO   mensagem de debug do perfil não encontrada")


path.write_text(text, encoding="utf-8")


# ============================================================
# 4. README SWITCH
# ============================================================

path = root / "ports/switch/README.md"
text = path.read_text(encoding="utf-8")

old = '''- starts from the cartridge boot sequence (`BOOT`), including the original
  Nintendo Presents sequence before the title screen;
'''

new = '''- starts directly in the cartridge intro (`INTROMAP`), bypassing the host
  pre-game setup; the intro opens with the original Nintendo Presents sequence;
'''

if new not in text:
    if old not in text:
        raise RuntimeError(
            "Descrição BOOT do README não encontrada"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print("PATCH   README: INTROMAP")
else:
    print("JA OK   README INTROMAP")


anchor = '''- uses a fullscreen 1280x720 SDL surface, which the system scales for the
  active display mode.
'''

replacement = '''- uses a fullscreen 1280x720 SDL surface, which the system scales for the
  active display mode; and
- uses the Switch EGL 60 Hz VSync as the sole production frame pacer instead
  of combining it with the desktop software presentation clock.
'''

if replacement not in text:
    if anchor not in text:
        raise RuntimeError(
            "Descrição da SDL surface não encontrada no README"
        )

    text = text.replace(
        anchor,
        replacement,
        1
    )

    print("PATCH   README: pacing 60 Hz")
else:
    print("JA OK   README pacing")

path.write_text(text, encoding="utf-8")


print()
print("Todos os patches foram aplicados.")
PY

echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check

echo
echo "Perfil Switch:"
grep -n \
    -A14 \
    'switch_runtime_profile' \
    include/starfox/app/platform_profile.hpp \
    | head -n 18

echo
echo "Teste de plataforma:"
cat tests/platform_profile_tests.cpp

echo
echo "Ocorrências dos pacers:"
grep -n \
    -E 'software_frame_pacer|wait_for_next_frame' \
    src/app/starfox_pc.cpp \
    include/starfox/app/platform_profile.hpp \
    tests/platform_profile_tests.cpp

echo
echo "============================================================"
echo "BUILD DESKTOP DE VALIDAÇÃO"
echo "============================================================"

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

ctest \
    --test-dir "$BUILD_DESKTOP" \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest.log"

echo
echo "============================================================"
echo "BUILD NINTENDO SWITCH"
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
    --verbose \
    2>&1 \
    | tee "$REPORT_DIR/build-switch.log"

NRO="$BUILD_SWITCH/ports/switch/starfox_switch.nro"

echo
echo "============================================================"
echo "VALIDAÇÃO DO NRO"
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
echo "VALIDAÇÃO DO CONTRATO SWITCH"
echo "============================================================"

grep -q \
    '"INTROMAP"' \
    include/starfox/app/platform_profile.hpp

grep -q \
    'DisplayMode::widescreen_16_9' \
    include/starfox/app/platform_profile.hpp

grep -q \
    '60U' \
    include/starfox/app/platform_profile.hpp

grep -q \
    'software_frame_pacer' \
    include/starfox/app/platform_profile.hpp

echo "OK: INTROMAP"
echo "OK: Original aplicado pelo runtime"
echo "OK: 20 Hz"
echo "OK: 60 FPS"
echo "OK: 16:9"
echo "OK: English"
echo "OK: Switch usa somente display VSync para pacing"

echo
echo "============================================================"
echo "PREPARANDO COMMIT"
echo "============================================================"

# O arquivo é apenas um log de build e não deve receber novas alterações.
git restore \
    -- build-switch-nro.log \
    2>/dev/null \
    || true

git add \
    include/starfox/app/platform_profile.hpp \
    tests/platform_profile_tests.cpp \
    src/app/starfox_pc.cpp \
    ports/switch/README.md \
    tools/scripts/finalize-switch-intro-and-60fps.sh

echo
echo "Arquivos no commit:"
git diff \
    --cached \
    --name-status

echo
echo "Resumo:"
git diff \
    --cached \
    --stat

echo
echo "============================================================"
echo "COMMIT"
echo "============================================================"

if git diff --cached --quiet
then
    echo "Nenhuma alteração nova para commit."
else
    git commit \
        -s \
        -m "Switch: boot intro directly and fix 60 FPS pacing"
fi

COMMIT_SHA="$(git rev-parse HEAD)"

echo
echo "Commit:"
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
echo "RESULTADO"
echo "============================================================"

echo
echo "Perfil final Switch:"
echo
echo "  Boot       : INTROMAP"
echo "  Primeira tela: Nintendo Presents"
echo "  Pre-game   : bypassado"
echo "  Experience : Original"
echo "  Game logic : fixed 20 Hz"
echo "  Render     : 60 FPS"
echo "  Display    : 16:9 widescreen"
echo "  Language   : English"
echo "  Pacing     : EGL/VSync only"
echo
echo "NRO:"
echo "  $NRO"
echo
echo "SHA256:"
cat "$REPORT_DIR/nro-sha256.txt"
echo
echo "Git:"
git log \
    -1 \
    --oneline \
    --decorate
echo
echo "Status:"
git status --short

{
    echo "STAR FOX ENHANCED — SWITCH INTRO + 60 FPS"
    echo
    echo "Commit:"
    echo "  $COMMIT_SHA"
    echo
    echo "Profile:"
    echo "  INTROMAP"
    echo "  ORIGINAL"
    echo "  20 Hz logic"
    echo "  60 FPS presentation"
    echo "  16:9 widescreen"
    echo "  English"
    echo "  display VSync pacing"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
