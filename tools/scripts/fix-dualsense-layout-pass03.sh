#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
OUT_DIR="$PROJECT_ROOT/out/dualsense-layout-pass03/$STAMP"
mkdir -p "$OUT_DIR" "$OUT_DIR/backup"

trap '
STATUS=$?
echo
echo "============================================================"
echo "SCRIPT INTERROMPIDO"
echo "============================================================"
echo "Código: $STATUS"
echo "Linha aproximada: $LINENO"
echo
echo "Cole aqui o conteúdo de:"
echo "  $OUT_DIR/report.txt"
echo
exit $STATUS
' ERR

echo "============================================================"
echo "STAR FOX ENHANCED — DUALSENSE LAYOUT PASS 03"
echo "============================================================"
echo

echo "[1/6] Localizando arquivos candidatos..."
rg -n --glob '*.cpp' --glob '*.hpp' \
  'dualsense|dualshock4|FIRE|BOMB|BOOST|BRAKE|PUSH START TO EXIT|draw_control_visual_profile|high_res_control_overlay' \
  src include \
  | tee "$OUT_DIR/report.txt"

echo
echo "[2/6] Fazendo backup dos arquivos mais prováveis..."
for f in \
  src/app/starfox_pc.cpp \
  src/app/runtime_input.cpp \
  src/app/control_visual_profile.cpp \
  src/app/control_visual_profiles.cpp \
  src/render/control_visual_profile.cpp \
  src/render/control_visual_profiles.cpp \
  include/starfox/app/control_visual_profile.hpp \
  include/starfox/app/control_visual_profiles.hpp
do
  if [[ -f "$f" ]]; then
    mkdir -p "$OUT_DIR/backup/$(dirname "$f")"
    cp -a "$f" "$OUT_DIR/backup/$f"
    printf 'BACKUP  %s\n' "$f"
  fi
done

echo
echo "[3/6] Aplicando correções automáticas..."
python3 <<'PY'
from pathlib import Path
import re

project = Path(".")
report_lines = []

def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")

def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")

candidates = [
    Path("src/app/starfox_pc.cpp"),
    Path("src/app/runtime_input.cpp"),
    Path("src/app/control_visual_profile.cpp"),
    Path("src/app/control_visual_profiles.cpp"),
    Path("src/render/control_visual_profile.cpp"),
    Path("src/render/control_visual_profiles.cpp"),
]

existing = [p for p in candidates if p.exists()]
if not existing:
    raise RuntimeError("Nenhum arquivo candidato de visual de controle foi encontrado.")

patched_any = False

for path in existing:
    text = read(path)
    original = text
    local_changes = []

    # =========================================================
    # 1) Ajuste fino de posição do overlay HD do DualSense
    # =========================================================
    if "STARFOX_DUALSENSE_PANEL_CENTER_PASS02" in text and "STARFOX_DUALSENSE_PASS03_NUDGE" not in text:
        pattern = re.compile(
            r'(const auto overlay_x\s*=\s*[\s\S]*?dualsense_visible_centre_in_crop;\n)',
            re.MULTILINE
        )
        match = pattern.search(text)
        if match:
            replacement = match.group(1) + '''
            // STARFOX_DUALSENSE_PASS03_NUDGE
            // Fine tuning from visual validation:
            // - move right a bit
            // - move up a bit
            constexpr float dualsense_nudge_x = 22.0F;
            constexpr float dualsense_nudge_y = -14.0F;
'''
            text = text[:match.start()] + replacement + text[match.end():]
            local_changes.append("inserido nudge do DualSense (+22 X, -14 Y)")

        # tenta aplicar o nudge no ponto de uso de overlay_x/overlay_y
        text = text.replace(
            "overlay_x,",
            "(overlay_x + dualsense_nudge_x),"
        )
        text = text.replace(
            "overlay_y,",
            "(overlay_y + dualsense_nudge_y),"
        )

    # =========================================================
    # 2) Ajuste do texto/legendas para não colidir com EXIT
    # =========================================================
    #
    # Procura bloco com FIRE/BOMB/BOOST/BRAKE e tenta deslocar.
    #
    if all(token in text for token in ["FIRE", "BOMB", "BOOST", "BRAKE"]):
        # caso haja constantes simples de coluna / linha
        replacements = [
            (r'(\blegend_x\s*=\s*)([0-9]+)(\s*;)', r'\g<1>650\g<3>'),
            (r'(\blegend_y\s*=\s*)([0-9]+)(\s*;)', r'\g<1>440\g<3>'),
            (r'(\baction_text_x\s*=\s*)([0-9]+)(\s*;)', r'\g<1>650\g<3>'),
            (r'(\baction_text_y\s*=\s*)([0-9]+)(\s*;)', r'\g<1>438\g<3>'),
            (r'(\bbutton_label_x\s*=\s*)([0-9]+)(\s*;)', r'\g<1>650\g<3>'),
            (r'(\bbutton_label_y\s*=\s*)([0-9]+)(\s*;)', r'\g<1>438\g<3>')
        ]
        for pat, repl in replacements:
            new_text = re.sub(pat, repl, text)
            if new_text != text:
                text = new_text
                local_changes.append(f"ajuste de constante por regex: {pat}")

    # =========================================================
    # 3) Inserir lembrete/placeholder textual para L1/R1/UP/DOWN
    # =========================================================
    #
    # O objetivo aqui é adicionar os textos extras, usando o mesmo
    # arquivo que já contém FIRE/BOMB/BOOST/BRAKE.
    #
    if all(token in text for token in ["FIRE", "BOMB", "BOOST", "BRAKE"]) and "ROLL" not in text:
        # Tenta expandir um array ou tabela textual simples.
        table_pattern = re.compile(
            r'(\{\s*"FIRE"\s*,[\s\S]*?\{\s*"BRAKE"\s*,[\s\S]*?\}\s*\};)',
            re.MULTILINE
        )
        m = table_pattern.search(text)
        if m:
            block = m.group(1)
            if '"ROLL"' not in block and '"UP"' not in block and '"DOWN"' not in block:
                expanded = block[:-2] + ',\n' + \
                    '        {"L1", "ROLL"},\n' + \
                    '        {"R1", "ROLL"},\n' + \
                    '        {"UP", "UP"},\n' + \
                    '        {"DOWN", "DOWN"}\n' + \
                    '    };'
                text = text.replace(block, expanded, 1)
                local_changes.append("tabela de legendas expandida com L1/R1/UP/DOWN")

    # =========================================================
    # 4) Inserir comentário-guia se nada de legendas foi encontrado
    # =========================================================
    if "FIRE" in text and "BOMB" in text and "BOOST" in text and "BRAKE" in text and "PASS03_CONTROL_NOTES" not in text:
        marker = "// PASS03_CONTROL_NOTES"
        insertion = '''
// PASS03_CONTROL_NOTES
// Layout alvo validado visualmente:
// - DualSense um pouco mais à direita e um pouco mais acima
// - Legendas da coluna direita mais altas, para não colidir com "PUSH START TO EXIT"
// - Acrescentar indicadores de:
//   * L1 = ROLL
//   * R1 = ROLL
//   * DPAD UP = UP
//   * DPAD DOWN = DOWN
'''
        text = insertion + text
        local_changes.append("comentário-guia PASS03 inserido")

    if text != original:
        write(path, text)
        patched_any = True
        report_lines.append(f"PATCH   {path}")
        for item in local_changes:
            report_lines.append(f"        - {item}")
    else:
        report_lines.append(f"SEM MUDANÇA {path}")

report = Path("out/dualsense-layout-pass03") / Path(sorted((Path("out/dualsense-layout-pass03")).glob("*"))[-1].name) / "patch-report.txt"
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text("\n".join(report_lines) + "\n", encoding="utf-8")

print("\n".join(report_lines))

if not patched_any:
    raise RuntimeError(
        "Nenhum patch automático foi aplicado. "
        "Cole aqui o conteúdo de out/dualsense-layout-pass03/*/report.txt"
    )
PY

echo
echo "[4/6] Checando diff..."
git diff --check
git diff --stat | tee "$OUT_DIR/diff-stat.txt"

echo
echo "[5/6] Build de validação..."
BUILD_DIR="$PROJECT_ROOT/build/linux-dualsense-layout-pass03"
cmake -S . -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DSTARFOX_BUILD_RUNTIME=ON \
  -DSTARFOX_BUILD_TESTS=ON

cmake --build "$BUILD_DIR" -j"$(nproc)" \
  2>&1 | tee "$OUT_DIR/build.log"

echo
echo "[6/6] Testes rápidos..."
ctest --test-dir "$BUILD_DIR" \
  -R 'starfox_control_visual_profile_tests|starfox_runtime_smoke$|starfox_runtime_smoke_ptbr$' \
  --output-on-failure \
  2>&1 | tee "$OUT_DIR/ctest.log"

echo
echo "============================================================"
echo "PASS 03 CONCLUÍDO"
echo "============================================================"
echo
echo "Relatórios:"
echo "  $OUT_DIR/report.txt"
echo "  $OUT_DIR/patch-report.txt"
echo "  $OUT_DIR/build.log"
echo "  $OUT_DIR/ctest.log"
echo
echo "Agora rode manualmente o binário e confira:"
echo "  1. se o DualSense subiu e foi mais para a direita;"
echo "  2. se a coluna da direita parou de colidir com PUSH START TO EXIT;"
echo "  3. se apareceram L1 / R1 / UP / DOWN."
