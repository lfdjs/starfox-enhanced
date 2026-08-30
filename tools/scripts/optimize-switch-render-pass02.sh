#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"
BUILD_SWITCH="$PROJECT_ROOT/build-switch"
BUILD_DESKTOP="$PROJECT_ROOT/build/linux-switch-perf02-validation"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/switch-render-pass02/$STAMP"

mkdir -p "$REPORT_DIR/backup"

echo "============================================================"
echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 02"
echo "OBJ/OAM tile-row cache + direct framebuffer writes"
echo "============================================================"
echo

FILES=(
    include/starfox/render/framebuffer.hpp
    src/render/sprite_renderer.cpp
)

for file in "${FILES[@]}"
do
    if [[ ! -f "$file" ]]
    then
        echo "ERRO: arquivo ausente:"
        echo "  $file"
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


def replace_once(text, old, new, description):
    if new in text:
        print(f"JA OK   {description}")
        return text

    if old not in text:
        raise RuntimeError(
            f"Trecho não encontrado: {description}"
        )

    print(f"PATCH   {description}")

    return text.replace(
        old,
        new,
        1
    )


# ============================================================
# 1. GARANTIR Framebuffer::row_data
#
# A Pass 01 já deve ter criado isto.
# Este bloco torna a Pass 02 segura caso ela seja executada
# isoladamente.
# ============================================================

path = root / "include/starfox/render/framebuffer.hpp"

text = path.read_text(
    encoding="utf-8"
)

if "std::uint8_t* row_data(" not in text:

    old = '''    [[nodiscard]] const std::vector<std::uint8_t>& pixels() const noexcept { return pixels_; }

    void resize(std::uint32_t width, std::uint32_t height) {
'''

    new = '''    [[nodiscard]] const std::vector<std::uint8_t>& pixels() const noexcept { return pixels_; }

    [[nodiscard]] std::uint8_t* row_data(
        std::uint32_t y) noexcept {

        return pixels_.data()
            + static_cast<std::size_t>(y) * width_;
    }

    [[nodiscard]] const std::uint8_t* row_data(
        std::uint32_t y) const noexcept {

        return pixels_.data()
            + static_cast<std::size_t>(y) * width_;
    }

    void resize(std::uint32_t width, std::uint32_t height) {
'''

    text = replace_once(
        text,
        old,
        new,
        "Framebuffer::row_data fallback"
    )

    path.write_text(
        text,
        encoding="utf-8"
    )

else:
    print(
        "JA OK   Framebuffer::row_data"
    )


# ============================================================
# 2. SpriteRenderer
# ============================================================

path = root / "src/render/sprite_renderer.cpp"

text = path.read_text(
    encoding="utf-8"
)


# ------------------------------------------------------------
# Substituir object_pixel() por decodificador de linha.
#
# object_pixel atual lê os quatro bitplanes novamente para
# cada pixel.
#
# O novo helper lê esses bitplanes uma vez e produz:
#
#     [p0 p1 p2 p3 p4 p5 p6 p7]
#
# ------------------------------------------------------------

begin = text.find(
    "std::uint8_t object_pixel("
)

if begin >= 0:

    end_marker = "\n\n\nconst char* hud_element_debug_name"

    end = text.find(
        end_marker,
        begin
    )

    if end < 0:
        raise RuntimeError(
            "Fim de object_pixel() não encontrado"
        )

    replacement = r'''using ObjectTileRow =
    std::array<std::uint8_t, 8>;

ObjectTileRow object_tile_row(
    const simulation::SnesPpuState& ppu,
    std::uint16_t tile_number,
    std::uint32_t tile_column,
    std::uint32_t source_y) noexcept {

    const auto table_base =
        static_cast<std::uint32_t>(
            ppu.object_select & 7U)
        * 0x2000U;

    const auto name_gap =
        static_cast<std::uint32_t>(
            ((ppu.object_select >> 3U)
                & 3U)
            + 1U)
        * 0x1000U;

    auto tile_base =
        table_base;

    if ((tile_number & 0x100U)
        != 0U) {

        tile_base +=
            name_gap;
    }

    const auto tile =
        static_cast<std::uint32_t>(
            tile_number & 0xffU)
        + (source_y >> 3U) * 16U
        + tile_column;

    const auto address =
        (tile_base * 2U
            + tile * 32U
            + (source_y & 7U)
                * 2U)
        & 0xffffU;

    const auto plane01 =
        static_cast<std::uint16_t>(
            ppu.vram[address])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (address + 1U)
                    & 0xffffU])
            << 8U);

    const auto plane23 =
        static_cast<std::uint16_t>(
            ppu.vram[
                (address + 16U)
                    & 0xffffU])
        | (static_cast<std::uint16_t>(
            ppu.vram[
                (address + 17U)
                    & 0xffffU])
            << 8U);

    ObjectTileRow result{};

    for (std::uint32_t x = 0U;
         x < result.size();
         ++x) {

        const auto mask =
            static_cast<std::uint8_t>(
                0x80U >> x);

        result[x] =
            static_cast<std::uint8_t>(
                ((plane01 & mask) != 0U
                    ? 1U : 0U)

                | ((plane01
                        & (static_cast<
                            std::uint16_t>(
                                mask)
                            << 8U))
                    != 0U
                    ? 2U : 0U)

                | ((plane23 & mask) != 0U
                    ? 4U : 0U)

                | ((plane23
                        & (static_cast<
                            std::uint16_t>(
                                mask)
                            << 8U))
                    != 0U
                    ? 8U : 0U));
    }

    return result;
}'''

    text = (
        text[:begin]
        + replacement
        + text[end:]
    )

    print(
        "PATCH   object_pixel -> object_tile_row"
    )

elif "ObjectTileRow object_tile_row(" in text:

    print(
        "JA OK   object_tile_row"
    )

else:

    raise RuntimeError(
        "Nem object_pixel nem object_tile_row encontrados"
    )


# ------------------------------------------------------------
# Hoist do getenv
# ------------------------------------------------------------

old = '''    const auto sizes = kObjectSizes[size_selection < kObjectSizes.size()
        ? size_selection : kObjectSizes.size() - 1U];

    // Lower OAM indices win sprite-to-sprite priority, so paint in reverse.
'''

new = '''    const auto sizes = kObjectSizes[size_selection < kObjectSizes.size()
        ? size_selection : kObjectSizes.size() - 1U];

    const auto target_width =
        static_cast<std::int32_t>(
            target.width());

    const auto target_height =
        static_cast<std::int32_t>(
            target.height());

    // getenv() is comparatively expensive on a console runtime. HUD OAM
    // discovery is a developer-only feature, so evaluate it once per pass
    // instead of once for every one of the 128 OAM records.
    const bool log_hud_oam =
        std::getenv(
            "STARFOX_LOG_HUD_OAM")
        != nullptr;

    // Lower OAM indices win sprite-to-sprite priority, so paint in reverse.
'''

text = replace_once(
    text,
    old,
    new,
    "hoist dimensions + STARFOX_LOG_HUD_OAM"
)


old = '''        if (std::getenv("STARFOX_LOG_HUD_OAM") != nullptr
            && hud_layout != nullptr
            && element.has_value()) {
'''

new = '''        if (log_hud_oam
            && hud_layout != nullptr
            && element.has_value()) {
'''

text = replace_once(
    text,
    old,
    new,
    "remove getenv from OAM loop"
)


# ------------------------------------------------------------
# OBJ pixel loop
# ------------------------------------------------------------

old = '''        for (std::uint32_t destination_y = 0; destination_y < size; ++destination_y) {
            const auto source_y = flip_y ? size - 1U - destination_y : destination_y;
            const auto raw_y = static_cast<std::int32_t>(y_byte)
                + object_offset.y +
                static_cast<std::int32_t>(destination_y);
            const std::array<std::int32_t, 2> screen_ys{raw_y, raw_y - 256};
            for (const auto screen_y : screen_ys) {
                if (screen_y < 0 || screen_y >= static_cast<std::int32_t>(target.height())) {
                    continue;
                }
                for (std::uint32_t destination_x = 0; destination_x < size; ++destination_x) {
                    const auto screen_x = x + object_origin + object_offset.x
                        + static_cast<std::int32_t>(destination_x);
                    if (!extend_horizontal
                        && (screen_x < horizontal_origin
                            || screen_x >= horizontal_origin + 256)) continue;
                    if (screen_x < 0
                        || screen_x >= static_cast<std::int32_t>(target.width())) continue;
                    const auto source_x = flip_x ? size - 1U - destination_x : destination_x;
                    const auto pixel = object_pixel(ppu, tile, source_x, source_y);
                    if (pixel == 0U) continue;
                    target.set(screen_x, screen_y, static_cast<std::uint8_t>(
                        128U + palette * 16U + pixel));
                }
            }
        }
'''

new = '''        const auto palette_base =
            static_cast<std::uint8_t>(
                128U
                + palette * 16U);

        const auto tile_columns =
            (size + 7U) >> 3U;

        // The largest SNES object supported by this renderer is 64 pixels
        // wide, therefore at most eight 8x8 tile columns exist in a row.
        std::array<ObjectTileRow, 8>
            decoded_rows{};

        for (std::uint32_t destination_y = 0;
             destination_y < size;
             ++destination_y) {

            const auto source_y =
                flip_y
                    ? size - 1U
                        - destination_y
                    : destination_y;

            // Decode every 8-pixel source tile row once. The previous path
            // decoded the same four SNES bitplanes again for every pixel.
            for (std::uint32_t tile_column = 0U;
                 tile_column < tile_columns;
                 ++tile_column) {

                decoded_rows[tile_column] =
                    object_tile_row(
                        ppu,
                        tile,
                        tile_column,
                        source_y);
            }

            const auto raw_y =
                static_cast<std::int32_t>(
                    y_byte)
                + object_offset.y
                + static_cast<std::int32_t>(
                    destination_y);

            const std::array<
                std::int32_t,
                2>
                screen_ys{
                    raw_y,
                    raw_y - 256};

            for (const auto screen_y :
                 screen_ys) {

                if (screen_y < 0
                    || screen_y
                        >= target_height) {

                    continue;
                }

                auto* const target_row =
                    target.row_data(
                        static_cast<
                            std::uint32_t>(
                                screen_y));

                for (std::uint32_t destination_x = 0;
                     destination_x < size;
                     ++destination_x) {

                    const auto screen_x =
                        x
                        + object_origin
                        + object_offset.x
                        + static_cast<
                            std::int32_t>(
                                destination_x);

                    if (!extend_horizontal
                        && (screen_x
                                < horizontal_origin
                            || screen_x
                                >= horizontal_origin
                                    + 256)) {

                        continue;
                    }

                    if (screen_x < 0
                        || screen_x
                            >= target_width) {

                        continue;
                    }

                    const auto source_x =
                        flip_x
                            ? size - 1U
                                - destination_x
                            : destination_x;

                    const auto tile_column =
                        source_x >> 3U;

                    const auto tile_pixel_x =
                        source_x & 7U;

                    const auto pixel =
                        decoded_rows[
                            tile_column][
                                tile_pixel_x];

                    if (pixel == 0U) {
                        continue;
                    }

                    target_row[
                        static_cast<
                            std::uint32_t>(
                                screen_x)] =
                        static_cast<
                            std::uint8_t>(
                                palette_base
                                + pixel);
                }
            }
        }
'''

text = replace_once(
    text,
    old,
    new,
    "OBJ tile-row cache + direct framebuffer write"
)


# ============================================================
# 3. HUD meters
#
# Estes retângulos são pequenos, mas aparecem constantemente.
# Em vez de executar bounds-check por pixel, recortamos a linha
# uma vez e usamos std::fill.
# ============================================================

old = '''    const auto solid = [&target](
        std::int32_t x,
        std::int32_t y,
        std::int32_t width,
        std::int32_t height,
        std::uint8_t colour) {
        for (std::int32_t row = 0; row < height; ++row) {
            for (std::int32_t column = 0; column < width; ++column) {
                target.set(x + column, y + row,
                    static_cast<std::uint8_t>(7U * 16U + colour));
            }
        }
    };
'''

new = '''    const auto solid = [&target](
        std::int32_t x,
        std::int32_t y,
        std::int32_t width,
        std::int32_t height,
        std::uint8_t colour) {

        if (width <= 0
            || height <= 0) {

            return;
        }

        const auto target_width =
            static_cast<std::int32_t>(
                target.width());

        const auto target_height =
            static_cast<std::int32_t>(
                target.height());

        const auto first_x =
            std::max<std::int32_t>(
                0,
                x);

        const auto final_x =
            std::min<std::int32_t>(
                target_width,
                x + width);

        if (first_x >= final_x) {
            return;
        }

        const auto indexed_colour =
            static_cast<std::uint8_t>(
                7U * 16U
                + colour);

        for (std::int32_t row = 0;
             row < height;
             ++row) {

            const auto destination_y =
                y + row;

            if (destination_y < 0
                || destination_y
                    >= target_height) {

                continue;
            }

            auto* const destination =
                target.row_data(
                    static_cast<
                        std::uint32_t>(
                            destination_y));

            std::fill(
                destination + first_x,
                destination + final_x,
                indexed_colour);
        }
    };
'''

text = replace_once(
    text,
    old,
    new,
    "HUD meter direct scanline fills"
)


path.write_text(
    text,
    encoding="utf-8"
)

print()
print(
    "Performance Pass 02 aplicada."
)
PY

echo
echo "============================================================"
echo "VALIDAÇÃO ESTRUTURAL"
echo "============================================================"

git diff --check

echo
echo "Trechos alterados:"
grep -n \
    -E 'object_tile_row|decoded_rows|target_row|log_hud_oam' \
    src/render/sprite_renderer.cpp \
    | head -n 80

echo
echo
echo "Diff:"
git diff \
    --stat \
    include/starfox/render/framebuffer.hpp \
    src/render/sprite_renderer.cpp

echo
echo "============================================================"
echo "BUILD + TESTES DESKTOP"
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
echo "PERFORMANCE PASS 02 CONCLUÍDA"
echo "============================================================"

echo
echo "Otimizações acumuladas:"
echo
echo "  PASS 01"
echo "    [✓] BG1 tile-row cache"
echo "    [✓] BG2 tile-row cache"
echo "    [✓] BG3 tile-row cache"
echo "    [✓] direct framebuffer rows"
echo "    [✓] IPO/LTO Switch"
echo
echo "  PASS 02"
echo "    [✓] OBJ/OAM tile-row cache"
echo "    [✓] OBJ direct framebuffer writes"
echo "    [✓] HUD meter scanline fill"
echo "    [✓] getenv removido do hot OAM loop"
echo
echo "Novo NRO:"
echo "  $NRO"
echo
echo "IMPORTANTE:"
echo "  não foi criado commit."
echo "  valide primeiro no Ryujinx."
echo
echo "Git status:"
git status --short

{
    echo "STAR FOX ENHANCED — SWITCH PERFORMANCE PASS 02"
    echo
    echo "NRO:"
    echo "  $NRO"
    echo
    echo "SHA256:"
    cat "$REPORT_DIR/nro-sha256.txt"
    echo
    echo "DIFF:"
    git diff --stat
} > "$REPORT_DIR/report-share.txt"

echo
echo "Relatório:"
echo "  $REPORT_DIR/report-share.txt"
