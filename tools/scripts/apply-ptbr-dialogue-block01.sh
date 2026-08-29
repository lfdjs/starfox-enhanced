#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
CATALOG="$PROJECT_ROOT/localization/pt_BR/dialogue.tsv"
BUILD_DIR="$PROJECT_ROOT/build/linux-ptbr-phase1"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/ptbr-dialogue-translations/$STAMP"

mkdir -p "$REPORT_DIR"

cd "$PROJECT_ROOT"

if [[ ! -f "$CATALOG" ]]; then
    echo "ERRO: catálogo PT-BR não encontrado:"
    echo "  $CATALOG"
    exit 1
fi

cp -a \
    "$CATALOG" \
    "$REPORT_DIR/dialogue.tsv.before"

export CATALOG

python3 <<'PY'
from pathlib import Path
import os

path = Path(os.environ["CATALOG"])

translations = {
    0x01F7EB: "Certo, Fox! Mostre do que é capaz!",
    0x01F814: "Passe por todos os anéis!",
    0x01F83F: "Use o controle tipo A ou B!",
    0x01F86B: "Ahhh... você é habilidoso, Fox!",
    0x01F8C1: "Aperte START e volte ao jogo, croac!",
    0x01F8F0: "Não acredito que Pepper vai nos testar!",
    0x01FADF: "Siga-me, Fox!",
    0x01FB0D: "Mantenha a formação!",
    0x01FB23: "O que deu em você hoje, Fox?!",
}

text = path.read_text(encoding="utf-8")
lines = text.splitlines()

found = set()
result = []

for line in lines:
    stripped = line.strip()

    if not stripped or stripped.startswith("#") or "\t" not in line:
        result.append(line)
        continue

    address_text, existing_text = line.split("\t", 1)

    try:
        address = int(address_text.strip(), 0)
    except ValueError:
        result.append(line)
        continue

    if address in translations:
        result.append(
            f"0x{address:06X}\t{translations[address]}"
        )
        found.add(address)
    else:
        result.append(line)

missing = [
    address
    for address in translations
    if address not in found
]

if missing:
    if result and result[-1] != "":
        result.append("")

    result.extend([
        "# ============================================================",
        "# BLOCO 01 — TREINAMENTO / INÍCIO",
        "# ============================================================",
    ])

    for address in missing:
        result.append(
            f"0x{address:06X}\t{translations[address]}"
        )

result.append("")

path.write_text(
    "\n".join(result),
    encoding="utf-8"
)

print()
print("Traduções instaladas:")
print()

for address, translation in translations.items():
    print(
        f"0x{address:06X}  {translation}"
    )
PY

echo
echo "============================================================"
echo "VALIDAÇÃO DO CATÁLOGO"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

path = Path("localization/pt_BR/dialogue.tsv")

text = path.read_text(encoding="utf-8")

addresses = {}

for number, line in enumerate(
    text.splitlines(),
    start=1
):
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        continue

    if "\t" not in line:
        raise SystemExit(
            f"Linha {number}: entrada sem TAB"
        )

    address_text, translation = line.split(
        "\t",
        1
    )

    try:
        address = int(
            address_text.strip(),
            0
        )
    except ValueError:
        raise SystemExit(
            f"Linha {number}: endereço inválido"
        )

    if address > 0xFFFFFF:
        raise SystemExit(
            f"Linha {number}: endereço > 24 bits"
        )

    if not translation:
        raise SystemExit(
            f"Linha {number}: tradução vazia"
        )

    if address in addresses:
        raise SystemExit(
            f"Endereço duplicado 0x{address:06X}: "
            f"linhas {addresses[address]} e {number}"
        )

    addresses[address] = number

expected = {
    0x01F7EB,
    0x01F814,
    0x01F83F,
    0x01F86B,
    0x01F8C1,
    0x01F8F0,
    0x01FADF,
    0x01FB0D,
    0x01FB23,
}

missing = expected - addresses.keys()

if missing:
    raise SystemExit(
        "Entradas ausentes: "
        + ", ".join(
            f"0x{x:06X}"
            for x in sorted(missing)
        )
    )

print(
    f"Catálogo válido: {len(addresses)} traduções."
)

print(
    "Bloco 01: 9/9 entradas presentes."
)
PY

echo
echo "============================================================"
echo "SMOKE PT-BR"
echo "============================================================"

SMOKE_LOG="$REPORT_DIR/runtime-smoke.log"

set +e

env \
    SDL_VIDEODRIVER=dummy \
    SDL_AUDIODRIVER=dummy \
    STARFOX_TEST_EXPERIENCE=ORIGINAL \
    STARFOX_TEST_LANGUAGE=PT_BR \
    STARFOX_TEST_FRAMES=12 \
    STARFOX_TEST_UNPACED=1 \
    "$BUILD_DIR/starfox_pc" \
    upstream-ultrastarfox/SF.SFC \
    upstream-ultrastarfox/SYMBOLS.TXT \
    BOOT \
    2>&1 \
    | tee "$SMOKE_LOG"

RC=${PIPESTATUS[0]}

set -e

if [[ "$RC" -ne 0 ]]; then
    echo
    echo "ERRO: runtime smoke retornou $RC"
    exit "$RC"
fi

if grep -q \
    'invalid PT-BR dialogue catalog' \
    "$SMOKE_LOG"
then
    echo
    echo "ERRO: runtime rejeitou o catálogo."
    exit 20
fi

echo
echo "============================================================"
echo "RESULTADO"
echo "============================================================"
echo
echo "Bloco PT-BR 01 instalado com sucesso."
echo
echo "Catálogo:"
echo "  $CATALOG"
echo
echo "Backup:"
echo "  $REPORT_DIR/dialogue.tsv.before"
echo
echo "Não é necessário recompilar o jogo."
