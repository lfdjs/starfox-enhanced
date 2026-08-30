#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
SOURCE="$PROJECT_ROOT/src/app/starfox_pc.cpp"
ASSET_DIR="$PROJECT_ROOT/assets/control_hints"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT_DIR="$PROJECT_ROOT/out/dualsense-layout-pass04/$STAMP"

mkdir -p "$OUT_DIR/backup"

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
echo "DUALSENSE LAYOUT — PASS 04"
echo "============================================================"
echo


# ============================================================
# 1. BACKUP
# ============================================================

echo "[1/7] Backup..."

cp -a \
    "$SOURCE" \
    "$OUT_DIR/backup/starfox_pc.cpp"

if [[ -f "$ASSET_DIR/dualsense_controls_hd_1024.qoi" ]]
then
    cp -a \
        "$ASSET_DIR/dualsense_controls_hd_1024.qoi" \
        "$OUT_DIR/backup/dualsense_controls_hd_1024.qoi"
fi

if [[ -f "$ASSET_DIR/dualsense_controls_hd_1024.png" ]]
then
    cp -a \
        "$ASSET_DIR/dualsense_controls_hd_1024.png" \
        "$OUT_DIR/backup/dualsense_controls_hd_1024.png"
fi


# ============================================================
# 2. LOCALIZAR NOVO QOI
# ============================================================

echo
echo "============================================================"
echo "[2/7] Procurando a nova arte DualSense"
echo "============================================================"

CURRENT_QOI="$ASSET_DIR/dualsense_controls_hd_1024.qoi"
NEW_QOI=""

SEARCH_DIRS=(
    "$HOME/Downloads"
    "$HOME/Documentos"
    "$HOME/Área de Trabalho"
    "$HOME/Desktop"
)

for directory in "${SEARCH_DIRS[@]}"
do
    [[ -d "$directory" ]] || continue

    while IFS= read -r candidate
    do
        [[ "$candidate" == "$CURRENT_QOI" ]] && continue

        NEW_QOI="$candidate"
        break

    done < <(
        find "$directory" \
            -maxdepth 4 \
            -type f \
            -name 'dualsense_controls_hd_1024.qoi' \
            -printf '%T@ %p\n' \
            2>/dev/null \
        | sort -nr \
        | cut -d' ' -f2-
    )

    [[ -n "$NEW_QOI" ]] && break
done


if [[ -n "$NEW_QOI" ]]
then

    echo "Nova arte encontrada:"
    echo "  $NEW_QOI"

    echo
    echo "SHA256 anterior:"
    sha256sum "$CURRENT_QOI" || true

    echo
    echo "SHA256 nova:"
    sha256sum "$NEW_QOI"

    cp -f \
        "$NEW_QOI" \
        "$CURRENT_QOI"

    echo
    echo "QOI atualizado."

else

    echo
    echo "AVISO:"
    echo "Não encontrei outro dualsense_controls_hd_1024.qoi"
    echo "fora do projeto."
    echo
    echo "O layout será corrigido usando o QOI atualmente presente."
fi


# PNG é apenas fonte/documentação visual; o runtime usa QOI.
CURRENT_PNG="$ASSET_DIR/dualsense_controls_hd_1024.png"
NEW_PNG=""

for directory in "${SEARCH_DIRS[@]}"
do
    [[ -d "$directory" ]] || continue

    while IFS= read -r candidate
    do
        [[ "$candidate" == "$CURRENT_PNG" ]] && continue

        NEW_PNG="$candidate"
        break

    done < <(
        find "$directory" \
            -maxdepth 4 \
            -type f \
            -name 'dualsense_controls_hd_1024.png' \
            -printf '%T@ %p\n' \
            2>/dev/null \
        | sort -nr \
        | cut -d' ' -f2-
    )

    [[ -n "$NEW_PNG" ]] && break
done

if [[ -n "$NEW_PNG" ]]
then
    cp -f \
        "$NEW_PNG" \
        "$CURRENT_PNG"

    echo "PNG de referência atualizado:"
    echo "  $NEW_PNG"
fi


# ============================================================
# 3. CORRIGIR POSICIONAMENTO
# ============================================================

echo
echo "============================================================"
echo "[3/7] Corrigindo o alinhamento"
echo "============================================================"

python3 <<'PY'
from pathlib import Path
import re

path = Path("src/app/starfox_pc.cpp")

text = path.read_text(
    encoding="utf-8"
)


# ------------------------------------------------------------
# Localiza o bloco do overlay de alta resolução.
#
# Não importa se estamos no código original, Pass01, Pass02 ou
# em uma tentativa intermediária: substituímos o bloco inteiro.
# ------------------------------------------------------------

pattern = re.compile(
    r'''        if \(high_res_control_overlay && control_overlay_texture_ != nullptr\) \{
.*?
        \}
        SDL_RenderPresent\(renderer_\);''',
    re.DOTALL
)

match = pattern.search(text)

if not match:
    raise RuntimeError(
        "Não foi possível localizar o bloco "
        "high_res_control_overlay."
    )


replacement = '''        if (high_res_control_overlay && control_overlay_texture_ != nullptr) {

            // STARFOX_DUALSENSE_PANEL_ALIGNMENT_PASS04
            //
            // CONT.SCR already reserves the cartridge-space rectangle:
            //
            //   x      = 13
            //   y      = 118
            //   width  = 145
            //
            // Widescreen adds viewport_origin to cartridge coordinates.
            //
            // Anchor the complete HD artwork to that exact panel instead of
            // centring it against the complete 16:9/21:9 framebuffer.

            constexpr float cartridge_width =
                256.0F;

            constexpr float panel_x =
                13.0F;

            constexpr float panel_y =
                118.0F;

            constexpr float panel_width =
                145.0F;

            constexpr float panel_height =
                71.0F;


            const auto viewport_origin =
                width > static_cast<std::uint32_t>(
                    cartridge_width)

                ? (
                    static_cast<float>(width)
                    - cartridge_width
                  ) * 0.5F

                : 0.0F;


            // The supplied 1024x1024 image has its complete controller/help
            // composition inside this source slice.
            const SDL_FRect source{
                0.0F,
                260.0F,
                1024.0F,
                500.0F
            };


            const SDL_FRect destination{
                viewport_origin + panel_x,
                panel_y,
                panel_width,
                panel_height
            };


            SDL_RenderTexture(
                renderer_,
                control_overlay_texture_,
                &source,
                &destination);
        }

        SDL_RenderPresent(renderer_);'''


text = (
    text[:match.start()]
    + replacement
    + text[match.end():]
)


path.write_text(
    text,
    encoding="utf-8"
)

print(
    "PATCH   overlay alinhado ao painel CONT.SCR"
)

print(
    "        x = viewport_origin + 13"
)

print(
    "        y = 118"
)

print(
    "        width = 145"
)

print(
    "        height = 71"
)
PY


# ============================================================
# 4. VERIFICAÇÕES
# ============================================================

echo
echo "============================================================"
echo "[4/7] Validando alterações"
echo "============================================================"

git diff --check

echo
echo "Marker:"
grep -n \
    'STARFOX_DUALSENSE_PANEL_ALIGNMENT_PASS04' \
    src/app/starfox_pc.cpp

echo
echo "Assets:"
ls -lh \
    assets/control_hints/dualsense_controls_hd_1024.*

echo
echo "Resumo:"
git diff --stat


# ============================================================
# 5. BUILD
# ============================================================

echo
echo "============================================================"
echo "[5/7] Build desktop"
echo "============================================================"

BUILD="$PROJECT_ROOT/build/linux-dualsense-pass04"

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
    -j"$(nproc)" \
    2>&1 \
    | tee "$OUT_DIR/build.log"


# ============================================================
# 6. TESTES
# ============================================================

echo
echo "============================================================"
echo "[6/7] Testes relacionados"
echo "============================================================"

ctest \
    --test-dir "$BUILD" \
    -R 'starfox_control_visual_profile_tests|starfox_runtime_smoke$|starfox_runtime_smoke_ptbr$' \
    --output-on-failure \
    2>&1 \
    | tee "$OUT_DIR/ctest.log"


# ============================================================
# 7. EXECUÇÃO MANUAL
# ============================================================

echo
echo "============================================================"
echo "[7/7] Executando a versão corrigida"
echo "============================================================"

BIN="$BUILD/starfox_pc"

test -x "$BIN"

echo
echo "Executável:"
echo "  $BIN"

echo
echo "Teste visual:"
echo
echo "  1. entrar em CONT.SCR"
echo "  2. verificar se o conjunto DualSense + textos"
echo "     está alinhado dentro da área esquerda"
echo "  3. confirmar que não invade PUSH START TO EXIT"
echo "  4. verificar D-pad UP/DOWN"
echo "  5. verificar os shoulder buttons L1/R1"
echo
echo "Ainda NÃO faça commit."
echo


set +e

"$BIN" 2>&1 \
    | tee "$OUT_DIR/runtime.log"

STATUS=${PIPESTATUS[0]}

set -e


echo
echo "============================================================"
echo "EXECUÇÃO FINALIZADA"
echo "============================================================"

echo
echo "Exit code:"
echo "  $STATUS"

echo
echo "Git status:"
git status --short

echo
echo "Relatórios:"
echo "  $OUT_DIR"
