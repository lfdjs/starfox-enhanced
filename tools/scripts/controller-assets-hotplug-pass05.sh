#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$HOME/Documentos/projetos_recompilacao_estatica/starfox-enhanced"

cd "$PROJECT_ROOT"

STAMP="$(date '+%Y%m%d-%H%M%S')"
REPORT_DIR="$PROJECT_ROOT/out/controller-assets-hotplug-pass05/$STAMP"

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
echo
echo "Relatório:"
echo "  '"$REPORT_DIR"'"
exit $STATUS
' ERR


echo "============================================================"
echo "STAR FOX ENHANCED"
echo "CONTROLLER ASSETS + SAFE HOTPLUG — PASS 05"
echo "============================================================"
echo


# ============================================================
# 1. VERIFICAR ASSETS
# ============================================================

echo "[1/10] Verificando assets..."

ASSETS=(
    "assets/control_hints/dualsense_controls_white_buttons.qoi"
    "assets/control_hints/dualshock4_controls_corrected.qoi"
    "assets/control_hints/xbox_controls_corrected.qoi"
)

for asset in "${ASSETS[@]}"
do
    if [[ ! -s "$asset" ]]
    then
        echo
        echo "ERRO:"
        echo "Asset não encontrado:"
        echo "  $asset"
        exit 20
    fi

    echo "OK: $asset"
done


echo
echo "Headers QOI:"

python3 <<'PY'
from pathlib import Path
import struct

files = [
    Path("assets/control_hints/dualsense_controls_white_buttons.qoi"),
    Path("assets/control_hints/dualshock4_controls_corrected.qoi"),
    Path("assets/control_hints/xbox_controls_corrected.qoi"),
]

for path in files:

    data = path.read_bytes()

    if data[:4] != b"qoif":
        raise RuntimeError(
            f"{path}: cabeçalho QOI inválido"
        )

    width, height = struct.unpack(
        ">II",
        data[4:12]
    )

    print(
        f"  {path.name}: {width}x{height}"
    )
PY


# ============================================================
# 2. BACKUPS
# ============================================================

echo
echo "============================================================"
echo "[2/10] Backups"
echo "============================================================"

FILES=(
    "src/app/starfox_pc.cpp"
    "src/app/control_visual_profile.cpp"
    "ports/switch/CMakeLists.txt"
)

for file in "${FILES[@]}"
do
    mkdir -p \
        "$REPORT_DIR/backup/$(dirname "$file")"

    cp -a \
        "$file" \
        "$REPORT_DIR/backup/$file"

    echo "BACKUP: $file"
done


# ============================================================
# 3. PATCH STARFOX_PC
# ============================================================

echo
echo "============================================================"
echo "[3/10] Aplicando sistema multi-overlay + hotplug seguro"
echo "============================================================"

python3 <<'PY'
from pathlib import Path
import re

path = Path("src/app/starfox_pc.cpp")

text = path.read_text(
    encoding="utf-8"
)

original = text


# ============================================================
# A. PresentationEffects passa a carregar o perfil, não bool.
# ============================================================

old = '''    bool high_res_control_overlay{};
'''

new = '''    // STARFOX_MULTI_CONTROL_OVERLAY_PROFILE
    std::optional<
        starfox::app::ControlVisualProfile>
        high_res_control_profile{};
'''

if "STARFOX_MULTI_CONTROL_OVERLAY_PROFILE" not in text:

    if old not in text:
        raise RuntimeError(
            "PresentationEffects.high_res_control_overlay não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   PresentationEffects usa ControlVisualProfile"
    )


# ============================================================
# B. Estrutura para cada texture QOI
# ============================================================

marker = '''struct QoiImage {
    std::uint32_t width{};
    std::uint32_t height{};
    std::vector<std::uint8_t> rgba;
};
'''

insert = '''struct QoiImage {
    std::uint32_t width{};
    std::uint32_t height{};
    std::vector<std::uint8_t> rgba;
};


// STARFOX_CONTROL_OVERLAY_ASSET
struct ControlOverlayAsset {
    starfox::app::ControlVisualProfile profile{
        starfox::app::ControlVisualProfile::
            generic_gamepad_pc};

    std::string_view filename;

    SDL_Texture* texture{};

    SDL_FRect source{};
};


SDL_FRect visible_qoi_bounds(
    const QoiImage& image) noexcept {

    if (image.width == 0U
        || image.height == 0U) {

        return {};
    }


    std::uint32_t left =
        image.width;

    std::uint32_t top =
        image.height;

    std::uint32_t right{};
    std::uint32_t bottom{};

    bool found{};


    for (std::uint32_t y = 0U;
         y < image.height;
         ++y) {

        for (std::uint32_t x = 0U;
             x < image.width;
             ++x) {

            const auto offset =
                (
                    static_cast<std::size_t>(y)
                    * image.width
                    + x
                ) * 4U;


            const auto red =
                image.rgba[offset];

            const auto green =
                image.rgba[offset + 1U];

            const auto blue =
                image.rgba[offset + 2U];

            const auto alpha =
                image.rgba[offset + 3U];


            // Transparent QOIs are the normal path.
            //
            // The RGB test also handles exported images whose
            // transparent canvas became opaque black.
            const auto visible =
                alpha >= 16U
                && (
                    red >= 8U
                    || green >= 8U
                    || blue >= 8U
                );


            if (!visible) {
                continue;
            }


            found = true;

            left =
                std::min(left, x);

            top =
                std::min(top, y);

            right =
                std::max(right, x);

            bottom =
                std::max(bottom, y);
        }
    }


    if (!found) {

        return SDL_FRect{
            0.0F,
            0.0F,
            static_cast<float>(
                image.width),
            static_cast<float>(
                image.height)
        };
    }


    constexpr std::uint32_t padding =
        4U;


    left =
        left > padding
        ? left - padding
        : 0U;

    top =
        top > padding
        ? top - padding
        : 0U;

    right =
        std::min(
            image.width - 1U,
            right + padding);

    bottom =
        std::min(
            image.height - 1U,
            bottom + padding);


    return SDL_FRect{
        static_cast<float>(left),
        static_cast<float>(top),
        static_cast<float>(
            right - left + 1U),
        static_cast<float>(
            bottom - top + 1U)
    };
}
'''

if "STARFOX_CONTROL_OVERLAY_ASSET" not in text:

    if marker not in text:
        raise RuntimeError(
            "QoiImage não encontrado"
        )

    text = text.replace(
        marker,
        insert,
        1
    )

    print(
        "PATCH   ControlOverlayAsset + crop automático"
    )


# ============================================================
# C. carregar plural
# ============================================================

text = text.replace(
    "load_high_res_control_overlay();",
    "load_high_res_control_overlays();"
)


# ============================================================
# D. destrutor
# ============================================================

old = '''    ~Window() {
        SDL_DestroyTexture(control_overlay_texture_);
        SDL_DestroyTexture(texture_);
        SDL_DestroyRenderer(renderer_);
        SDL_DestroyWindow(window_);
    }
'''

new = '''    ~Window() {

        for (auto& overlay :
             control_overlay_assets_) {

            SDL_DestroyTexture(
                overlay.texture);

            overlay.texture =
                nullptr;
        }

        SDL_DestroyTexture(texture_);
        SDL_DestroyRenderer(renderer_);
        SDL_DestroyWindow(window_);
    }
'''

if old in text:

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   destrutor limpa todas as textures"
    )


# ============================================================
# E. apresentação respeitando wipe
# ============================================================

pattern = re.compile(
    r'''        // STARFOX_CONTROL_OVERLAY_WIPE_FIX
.*?
        present_rgba_pixels\(
            framebuffer\.width\(\),
            framebuffer\.height\(\),
            rgba_,
            show_high_res_control_overlay\);''',
    re.DOTALL
)

replacement = '''        // STARFOX_CONTROL_OVERLAY_WIPE_FIX_V2
        auto visible_control_profile =
            effects.high_res_control_profile;

        if (effects.wipe.active) {
            visible_control_profile.reset();
        }

        present_rgba_pixels(
            framebuffer.width(),
            framebuffer.height(),
            rgba_,
            visible_control_profile);'''

if "STARFOX_CONTROL_OVERLAY_WIPE_FIX_V2" not in text:

    match = pattern.search(text)

    if not match:
        raise RuntimeError(
            "Bloco CONTROL_OVERLAY_WIPE_FIX não encontrado"
        )

    text = (
        text[:match.start()]
        + replacement
        + text[match.end():]
    )

    print(
        "PATCH   wipe controla perfil HD"
    )


# ============================================================
# F. load_high_res_control_overlay -> plural
# ============================================================

pattern = re.compile(
    r'''    void load_high_res_control_overlay\(\) \{
.*?
    \}

    void set_windowed_size''',
    re.DOTALL
)

replacement = '''    void load_high_res_control_overlays() {

        for (auto& overlay :
             control_overlay_assets_) {

            std::vector<
                std::filesystem::path>
                candidates;


#if defined(STARFOX_SWITCH_RUNTIME)

            candidates.emplace_back(
                std::filesystem::path{
                    "romfs:/control_hints"}
                / overlay.filename);

#else

            candidates.emplace_back(
                std::filesystem::current_path()
                / "assets/control_hints"
                / overlay.filename);


            if (const auto* base =
                    SDL_GetBasePath();
                base != nullptr) {

                const auto executable =
                    std::filesystem::path{
                        base};


                candidates.emplace_back(
                    executable
                    / "assets/control_hints"
                    / overlay.filename);


                candidates.emplace_back(
                    executable
                        .parent_path()
                        .parent_path()
                    / "assets/control_hints"
                    / overlay.filename);
            }

#endif


            for (const auto& candidate :
                 candidates) {

                const auto image =
                    load_qoi(candidate);


                if (!image) {
                    continue;
                }


                overlay.texture =
                    SDL_CreateTexture(
                        renderer_,
                        SDL_PIXELFORMAT_RGBA32,
                        SDL_TEXTUREACCESS_STATIC,
                        static_cast<int>(
                            image->width),
                        static_cast<int>(
                            image->height));


                if (overlay.texture
                    == nullptr) {

                    continue;
                }


                if (!SDL_UpdateTexture(
                        overlay.texture,
                        nullptr,
                        image->rgba.data(),
                        static_cast<int>(
                            image->width
                            * 4U))) {

                    SDL_DestroyTexture(
                        overlay.texture);

                    overlay.texture =
                        nullptr;

                    continue;
                }


                SDL_SetTextureBlendMode(
                    overlay.texture,
                    SDL_BLENDMODE_BLEND);


                SDL_SetTextureScaleMode(
                    overlay.texture,
                    SDL_SCALEMODE_NEAREST);


                overlay.source =
                    visible_qoi_bounds(
                        *image);


                break;
            }
        }
    }


    [[nodiscard]]
    const ControlOverlayAsset*
    control_overlay_for(
        starfox::app::ControlVisualProfile
            profile) const noexcept {

        const auto found =
            std::find_if(
                control_overlay_assets_
                    .begin(),
                control_overlay_assets_
                    .end(),

                [profile](
                    const auto& overlay) {

                    return overlay.profile
                        == profile;
                });


        return found
                != control_overlay_assets_
                    .end()
            && found->texture
                != nullptr

            ? &*found
            : nullptr;
    }


    void set_windowed_size'''

if "control_overlay_for(" not in text:

    match = pattern.search(text)

    if not match:
        raise RuntimeError(
            "load_high_res_control_overlay() não encontrado"
        )

    text = (
        text[:match.start()]
        + replacement
        + text[match.end():]
    )

    print(
        "PATCH   loader QOI agora suporta PS4/PS5/Xbox"
    )


# ============================================================
# G. present_rgba_pixels assinatura
# ============================================================

old = '''    void present_rgba_pixels(std::uint32_t width, std::uint32_t height,
        std::span<const std::uint8_t> rgba, bool high_res_control_overlay) {
'''

new = '''    void present_rgba_pixels(
        std::uint32_t width,
        std::uint32_t height,
        std::span<const std::uint8_t> rgba,
        std::optional<
            starfox::app::ControlVisualProfile>
            high_res_control_profile) {
'''

if old in text:

    text = text.replace(
        old,
        new,
        1
    )


# present_rgba() passes false currently.
text = text.replace(
    '''        present_rgba_pixels(width, height, rgba_, false);
''',
    '''        present_rgba_pixels(
            width,
            height,
            rgba_,
            std::nullopt);
'''
)


# ============================================================
# H. substituir bloco de render do overlay
# ============================================================

pattern = re.compile(
    r'''        if \(high_res_control_overlay && control_overlay_texture_ != nullptr\) \{
.*?
        \}

        SDL_RenderPresent\(renderer_\);''',
    re.DOTALL
)

replacement = '''        if (high_res_control_profile) {

            const auto* overlay =
                control_overlay_for(
                    *high_res_control_profile);


            if (overlay != nullptr) {

                // STARFOX_MULTI_CONTROL_OVERLAY_RENDER
                //
                // Fit the visible part of each QOI into the same
                // cartridge-space panel while preserving aspect ratio.

                constexpr float cartridge_width =
                    256.0F;

                constexpr float panel_x =
                    13.0F;

                constexpr float panel_y =
                    118.0F;

                constexpr float panel_width =
                    145.0F;

                constexpr float panel_height =
                    91.0F;


                const auto viewport_origin =
                    width
                        > static_cast<
                            std::uint32_t>(
                                cartridge_width)

                    ? (
                        static_cast<float>(
                            width)
                        - cartridge_width
                      ) * 0.5F

                    : 0.0F;


                const auto aspect =
                    overlay->source.h > 0.0F

                    ? overlay->source.w
                        / overlay->source.h

                    : 1.0F;


                auto destination_width =
                    panel_width;

                auto destination_height =
                    destination_width
                    / aspect;


                if (destination_height
                    > panel_height) {

                    destination_height =
                        panel_height;

                    destination_width =
                        destination_height
                        * aspect;
                }


                const SDL_FRect destination{

                    viewport_origin
                        + panel_x
                        + (
                            panel_width
                            - destination_width
                          ) * 0.5F,

                    panel_y
                        + (
                            panel_height
                            - destination_height
                          ) * 0.5F,

                    destination_width,
                    destination_height
                };


                SDL_RenderTexture(
                    renderer_,
                    overlay->texture,
                    &overlay->source,
                    &destination);
            }
        }

        SDL_RenderPresent(renderer_);'''

if "STARFOX_MULTI_CONTROL_OVERLAY_RENDER" not in text:

    match = pattern.search(text)

    if not match:
        raise RuntimeError(
            "Render antigo do overlay não encontrado"
        )

    text = (
        text[:match.start()]
        + replacement
        + text[match.end():]
    )

    print(
        "PATCH   render escolhe asset por perfil"
    )


# ============================================================
# I. substituir membro texture único
# ============================================================

old = '''    SDL_Window* window_{};
    SDL_Renderer* renderer_{};
    SDL_Texture* texture_{};
    SDL_Texture* control_overlay_texture_{};
'''

new = '''    SDL_Window* window_{};
    SDL_Renderer* renderer_{};
    SDL_Texture* texture_{};

    // STARFOX_MULTI_CONTROL_OVERLAY_TEXTURES
    std::array<ControlOverlayAsset, 3>
        control_overlay_assets_{{
            {
                starfox::app::
                    ControlVisualProfile::
                        dualsense,
                "dualsense_controls_white_buttons.qoi"
            },
            {
                starfox::app::
                    ControlVisualProfile::
                        dualshock4,
                "dualshock4_controls_corrected.qoi"
            },
            {
                starfox::app::
                    ControlVisualProfile::
                        xbox,
                "xbox_controls_corrected.qoi"
            },
        }};
'''

if "STARFOX_MULTI_CONTROL_OVERLAY_TEXTURES" not in text:

    if old not in text:
        raise RuntimeError(
            "Membro control_overlay_texture_ não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )

    print(
        "PATCH   3 textures de controle"
    )


# ============================================================
# J. HOTPLUG — substituir bloco de gerenciamento
# ============================================================

start = text.find(
    "        AudioOutput audio;\n"
)

end = text.find(
    "        starfox::app::InputBindings bindings;\n",
    start
)

if start < 0 or end < 0:
    raise RuntimeError(
        "Bloco inicial de gamepads não encontrado"
    )


current = text[start:end]

replacement = '''        AudioOutput audio;

        auto gamepads =
            starfox::app::
                open_player_gamepads();


        // STARFOX_GAMEPAD_ID_CACHE_PASS05
        //
        // SDL_Gamepad* may outlive the physical connection until
        // SDL_CloseGamepad(), but we must never need to query a
        // potentially removed handle merely to discover its ID.

        std::vector<SDL_JoystickID>
            gamepad_ids;


        const auto rebuild_gamepad_ids =
            [&] {

            gamepad_ids.clear();

            gamepad_ids.reserve(
                gamepads.size());


            for (auto* opened :
                 gamepads) {

                gamepad_ids.push_back(
                    opened != nullptr

                    ? SDL_GetGamepadID(
                        opened)

                    : SDL_JoystickID{});
            }
        };


        rebuild_gamepad_ids();


        SDL_Gamepad* gamepad =
            gamepads.empty()
            ? nullptr
            : gamepads.front();


        SDL_JoystickID preferred_gamepad_id =
            gamepad_ids.empty()
            ? SDL_JoystickID{}
            : gamepad_ids.front();


        bool keyboard_control_active =
            gamepad == nullptr;


        const auto close_gamepads =
            [&] {

            // Do not call SDL_GetGamepadID here.
            //
            // Cached IDs remain the only identity source once a
            // removal event has been observed.

            for (auto* opened :
                 gamepads) {

                if (opened != nullptr) {

                    SDL_CloseGamepad(
                        opened);
                }
            }


            gamepads.clear();
            gamepad_ids.clear();

            gamepad = nullptr;
        };


        const auto select_gamepad_by_id =
            [&](SDL_JoystickID identifier)
                noexcept {

            if (identifier == 0U) {
                return false;
            }


            const auto count =
                std::min(
                    gamepads.size(),
                    gamepad_ids.size());


            for (std::size_t index = 0U;
                 index < count;
                 ++index) {

                if (gamepad_ids[index]
                    != identifier) {

                    continue;
                }


                if (gamepads[index]
                    == nullptr) {

                    continue;
                }


                gamepad =
                    gamepads[index];

                preferred_gamepad_id =
                    identifier;

                return true;
            }


            return false;
        };


        const auto refresh_gamepads =
            [&] {

            const auto previous_preferred =
                preferred_gamepad_id;


            close_gamepads();


            gamepads =
                starfox::app::
                    open_player_gamepads();


            rebuild_gamepad_ids();


            gamepad =
                gamepads.empty()
                ? nullptr
                : gamepads.front();


            preferred_gamepad_id =
                gamepad_ids.empty()
                ? SDL_JoystickID{}
                : gamepad_ids.front();


            if (previous_preferred
                != 0U) {

                static_cast<void>(
                    select_gamepad_by_id(
                        previous_preferred));
            }


            if (gamepad == nullptr) {

                keyboard_control_active =
                    true;
            }
        };

'''

text = (
    text[:start]
    + replacement
    + text[end:]
)

print(
    "PATCH   IDs de gamepad agora são cacheados"
)


# ============================================================
# K. GAMEPAD_REMOVED invalida imediatamente o ativo
# ============================================================

pattern = re.compile(
    r'''                \} else if \(
                    event\.type == SDL_EVENT_GAMEPAD_ADDED
                    \|\| event\.type == SDL_EVENT_GAMEPAD_REMOVED\) \{

.*?
                    gamepads_dirty = true;
                \}''',
    re.DOTALL
)

replacement = '''                } else if (
                    event.type
                        == SDL_EVENT_GAMEPAD_ADDED
                    || event.type
                        == SDL_EVENT_GAMEPAD_REMOVED) {

                    // STARFOX_GAMEPAD_REMOVAL_GUARD_PASS05
                    //
                    // As soon as SDL reports removal, stop exposing
                    // that raw SDL_Gamepad* to every remaining event
                    // in this poll batch.

                    if (event.type
                            == SDL_EVENT_GAMEPAD_REMOVED
                        && event.gdevice.which
                            == preferred_gamepad_id) {

                        gamepad =
                            nullptr;

                        preferred_gamepad_id =
                            SDL_JoystickID{};

                        keyboard_control_active =
                            true;
                    }


                    gamepads_dirty =
                        true;
                }'''

if "STARFOX_GAMEPAD_REMOVAL_GUARD_PASS05" not in text:

    match = pattern.search(text)

    if not match:
        raise RuntimeError(
            "GAMEPAD_ADDED/REMOVED não encontrado"
        )

    text = (
        text[:match.start()]
        + replacement
        + text[match.end():]
    )

    print(
        "PATCH   controle removido é invalidado imediatamente"
    )


# ============================================================
# L. remap nunca pede ID ao pointer
# ============================================================

text = text.replace(
    '''event.gbutton.which == SDL_GetGamepadID(gamepad)''',
    '''event.gbutton.which == preferred_gamepad_id'''
)

text = text.replace(
    '''event.gaxis.which == SDL_GetGamepadID(gamepad)''',
    '''event.gaxis.which == preferred_gamepad_id'''
)


# ============================================================
# M. PS4 + PS5 + XBOX habilitados
# ============================================================

pattern = re.compile(
    r'''            const auto playstation_control_visual =
.*?
            const auto custom_control_visual_ready =
                control_screen_ready
                && playstation_control_visual;''',
    re.DOTALL
)

replacement = '''            // STARFOX_HIGH_RES_CONTROLLER_PROFILES_PASS05
            const auto high_res_control_visual =
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

                    || detected_control_profile
                        == starfox::app::
                            ControlVisualProfile::
                                xbox
                );


            const auto custom_control_visual_ready =
                control_screen_ready
                && high_res_control_visual;'''

if "STARFOX_HIGH_RES_CONTROLLER_PROFILES_PASS05" not in text:

    match = pattern.search(text)

    if not match:
        raise RuntimeError(
            "playstation_control_visual não encontrado"
        )

    text = (
        text[:match.start()]
        + replacement
        + text[match.end():]
    )

    print(
        "PATCH   PS4 + PS5 + Xbox habilitados"
    )


# ============================================================
# N. PresentationEffects recebe perfil
# ============================================================

pattern = re.compile(
    r'''            // STARFOX_HD_CONTROL_READY_PASS02
            presentation_effects\.high_res_control_overlay =
.*?
                            dualsense;''',
    re.DOTALL
)

replacement = '''            // STARFOX_HD_CONTROL_PROFILE_PASS05
            presentation_effects.high_res_control_profile =
                custom_control_visual_ready

                ? std::optional<
                    starfox::app::
                        ControlVisualProfile>{
                            detected_control_profile}

                : std::nullopt;'''

if "STARFOX_HD_CONTROL_PROFILE_PASS05" not in text:

    match = pattern.search(text)

    if not match:
        raise RuntimeError(
            "high_res_control_overlay assignment não encontrado"
        )

    text = (
        text[:match.start()]
        + replacement
        + text[match.end():]
    )

    print(
        "PATCH   PresentationEffects seleciona QOI"
    )


path.write_text(
    text,
    encoding="utf-8"
)

print()
print("starfox_pc.cpp atualizado.")
PY


# ============================================================
# 4. CONTROL_VISUAL_PROFILE
# ============================================================

echo
echo "============================================================"
echo "[4/10] Desativando procedural para os 3 QOI HD"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

path = Path(
    "src/app/control_visual_profile.cpp"
)

text = path.read_text(
    encoding="utf-8"
)

old = '''    if (profile == ControlVisualProfile::dualsense) return;
'''

new = '''    // STARFOX_HD_PROFILE_PANEL_ONLY_PASS05
    //
    // These profiles use their QOI artwork in the SDL presentation
    // pass. Keep only the cleaned cartridge panel underneath.
    if (profile == ControlVisualProfile::dualsense
        || profile == ControlVisualProfile::dualshock4
        || profile == ControlVisualProfile::xbox) {

        return;
    }
'''

if "STARFOX_HD_PROFILE_PANEL_ONLY_PASS05" not in text:

    if old not in text:
        raise RuntimeError(
            "early-return DualSense não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )


path.write_text(
    text,
    encoding="utf-8"
)

print(
    "PATCH   PS4/PS5/Xbox usam somente QOI HD"
)
PY


# ============================================================
# 5. SWITCH ROMFS
# ============================================================

echo
echo "============================================================"
echo "[5/10] Atualizando RomFS dos layouts"
echo "============================================================"

python3 <<'PY'
from pathlib import Path

path = Path(
    "ports/switch/CMakeLists.txt"
)

text = path.read_text(
    encoding="utf-8"
)

old = '''configure_file(
    "${PROJECT_SOURCE_DIR}/assets/control_hints/dualsense_controls_hd_1024.qoi"
    "${switch_romfs}/control_hints/dualsense_controls_hd_1024.qoi"
    COPYONLY)
'''

new = '''# STARFOX_CONTROL_HINT_ROMFS_PASS05
foreach(control_hint_asset
    dualsense_controls_white_buttons.qoi
    dualshock4_controls_corrected.qoi
    xbox_controls_corrected.qoi)

    configure_file(
        "${PROJECT_SOURCE_DIR}/assets/control_hints/${control_hint_asset}"
        "${switch_romfs}/control_hints/${control_hint_asset}"
        COPYONLY)

endforeach()
'''

if "STARFOX_CONTROL_HINT_ROMFS_PASS05" not in text:

    if old not in text:
        raise RuntimeError(
            "configure_file DualSense RomFS não encontrado"
        )

    text = text.replace(
        old,
        new,
        1
    )


path.write_text(
    text,
    encoding="utf-8"
)

print(
    "PATCH   RomFS contém PS4/PS5/Xbox"
)
PY


# ============================================================
# 6. CHECKS
# ============================================================

echo
echo "============================================================"
echo "[6/10] Verificações estáticas"
echo "============================================================"

git diff --check

echo
echo "Markers:"

grep -n \
    'STARFOX_MULTI_CONTROL_OVERLAY\|STARFOX_GAMEPAD_ID_CACHE_PASS05\|STARFOX_GAMEPAD_REMOVAL_GUARD_PASS05\|STARFOX_HIGH_RES_CONTROLLER_PROFILES_PASS05\|STARFOX_HD_PROFILE_PANEL_ONLY_PASS05\|STARFOX_CONTROL_HINT_ROMFS_PASS05' \
    src/app/starfox_pc.cpp \
    src/app/control_visual_profile.cpp \
    ports/switch/CMakeLists.txt

echo
echo "Diff:"

git diff --stat

git diff > \
    "$REPORT_DIR/pass05.diff"


# ============================================================
# 7. BUILD DESKTOP
# ============================================================

echo
echo "============================================================"
echo "[7/10] Build desktop RelWithDebInfo"
echo "============================================================"

BUILD_DESKTOP="$PROJECT_ROOT/build/linux-controller-pass05"

cmake \
    -S . \
    -B "$BUILD_DESKTOP" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DSTARFOX_BUILD_RUNTIME=ON \
    -DSTARFOX_BUILD_TESTS=ON \
    -DSTARFOX_BUILD_SWITCH=OFF

cmake \
    --build "$BUILD_DESKTOP" \
    -j"$(nproc)" \
    2>&1 \
    | tee "$REPORT_DIR/build-desktop.log"


# ============================================================
# 8. TESTES
# ============================================================

echo
echo "============================================================"
echo "[8/10] Testes"
echo "============================================================"

ctest \
    --test-dir "$BUILD_DESKTOP" \
    --output-on-failure \
    2>&1 \
    | tee "$REPORT_DIR/ctest.log"


echo
echo "============================================================"
echo "RESUMO CTEST"
echo "============================================================"

grep -E \
    'tests passed|tests failed|Total Test time|FAILED' \
    "$REPORT_DIR/ctest.log" \
    || true


# ============================================================
# 9. BUILD SWITCH
# ============================================================

echo
echo "============================================================"
echo "[9/10] Build Nintendo Switch"
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


# ============================================================
# 10. EXECUÇÃO MANUAL
# ============================================================

echo
echo "============================================================"
echo "[10/10] TESTE MANUAL DE HOTPLUG"
echo "============================================================"

BIN="$BUILD_DESKTOP/starfox_pc"

test -x "$BIN"

echo
echo "Executável:"
echo "  $BIN"

echo
echo "TESTE NA SEGUINTE ORDEM:"
echo
echo "  1. Inicie com DualSense."
echo "  2. Abra CONT.SCR."
echo "     -> deve aparecer layout PS5."
echo
echo "  3. Conecte DualShock 4."
echo "  4. Pressione um botão do DS4."
echo "     -> layout deve mudar para PS4."
echo
echo "  5. Pressione novamente o DualSense."
echo "     -> layout deve voltar para PS5."
echo
echo "  6. Conecte Xbox."
echo "  7. Pressione um botão Xbox."
echo "     -> layout deve mudar para Xbox."
echo
echo "  8. Alterne PS4 <-> PS5 <-> Xbox."
echo
echo "  9. Desconecte o controle ATIVO."
echo "     -> jogo não pode crashar."
echo
echo " 10. Pressione o teclado."
echo "     -> jogo não pode crashar."
echo
echo " 11. Conecte novamente qualquer controle."
echo " 12. Pressione um botão."
echo "     -> controle deve tornar-se ativo."
echo
echo " 13. Repita desconectar/reconectar algumas vezes."
echo
echo "Nenhum commit será criado nesta etapa."
echo

ulimit -c unlimited || true


set +e

"$BIN" 2>&1 \
    | tee "$REPORT_DIR/runtime.log"

GAME_STATUS=${PIPESTATUS[0]}

set -e


echo
echo "============================================================"
echo "EXECUÇÃO ENCERRADA"
echo "============================================================"

echo
echo "Exit code:"
echo "  $GAME_STATUS"


if [[ "$GAME_STATUS" -ne 0 ]]
then

    echo
    echo "Runtime terminou de forma anormal."

    if command -v coredumpctl >/dev/null 2>&1
    then

        echo
        echo "Coredump:"

        coredumpctl \
            --no-pager \
            info \
            "$BIN" \
            2>/dev/null \
            | tail -n 160 \
            | tee "$REPORT_DIR/coredump.txt" \
            || true
    fi
fi


echo
echo "============================================================"
echo "PASS 05 FINALIZADO"
echo "============================================================"

echo
echo "Status:"
git status --short

echo
echo "Relatórios:"
echo "  $REPORT_DIR"
