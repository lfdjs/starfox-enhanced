#include "starfox/app/native_ui.hpp"
#include "starfox/app/native_font.hpp"

#include <SDL3/SDL.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>

namespace starfox::app {
namespace {

struct NativeColour {
    std::uint8_t r{};
    std::uint8_t g{};
    std::uint8_t b{};
    std::uint8_t a{255U};
};

struct NativeRect {
    float x{};
    float y{};
    float w{};
    float h{};
};

std::uint8_t fade_component(
    std::uint8_t value,
    std::uint8_t brightness) noexcept {

    brightness =
        std::min<std::uint8_t>(
            brightness,
            15U);

    return static_cast<std::uint8_t>(
        (
            static_cast<unsigned>(value)
            * brightness
        ) / 15U);
}

NativeColour fade_colour(
    NativeColour colour,
    std::uint8_t brightness) noexcept {

    colour.r =
        fade_component(
            colour.r,
            brightness);

    colour.g =
        fade_component(
            colour.g,
            brightness);

    colour.b =
        fade_component(
            colour.b,
            brightness);

    return colour;
}

void set_colour(
    SDL_Renderer* renderer,
    NativeColour colour,
    std::uint8_t brightness) noexcept {

    colour =
        fade_colour(
            colour,
            brightness);

    static_cast<void>(
        SDL_SetRenderDrawColor(
            renderer,
            colour.r,
            colour.g,
            colour.b,
            colour.a));
}

void fill_rect(
    SDL_Renderer* renderer,
    const NativeRect& rect,
    NativeColour colour,
    std::uint8_t brightness) noexcept {

    set_colour(
        renderer,
        colour,
        brightness);

    const SDL_FRect output{
        rect.x,
        rect.y,
        rect.w,
        rect.h
    };

    static_cast<void>(
        SDL_RenderFillRect(
            renderer,
            &output));
}

void stroke_rect(
    SDL_Renderer* renderer,
    const NativeRect& rect,
    float thickness,
    NativeColour colour,
    std::uint8_t brightness) noexcept {

    fill_rect(
        renderer,
        {
            rect.x,
            rect.y,
            rect.w,
            thickness
        },
        colour,
        brightness);

    fill_rect(
        renderer,
        {
            rect.x,
            rect.y
                + rect.h
                - thickness,
            rect.w,
            thickness
        },
        colour,
        brightness);

    fill_rect(
        renderer,
        {
            rect.x,
            rect.y,
            thickness,
            rect.h
        },
        colour,
        brightness);

    fill_rect(
        renderer,
        {
            rect.x
                + rect.w
                - thickness,
            rect.y,
            thickness,
            rect.h
        },
        colour,
        brightness);
}




// STARFOX_NATIVE_UI_FREETYPE_PASS05
//
// Font rendering is now delegated to NativeFont / FreeType.
// The layout code below continues using its original "pixel"
// sizing units, but text_width() and draw_text() translate them
// into actual scalable font sizes.

float text_width(
    std::string_view text,
    float pixel) noexcept {

    const auto height =
        std::max(
            8.0F,
            7.0F
                * pixel);


    return starfox::app::
        measure_native_ui_text(
            text,
            height);
}


void draw_text(
    SDL_Renderer* renderer,
    std::string_view text,
    float x,
    float y,
    float pixel,
    NativeColour colour,
    std::uint8_t brightness) noexcept {

    const auto height =
        std::max(
            8.0F,
            7.0F
                * pixel);


    starfox::app::
        draw_native_ui_text(
            renderer,
            text,
            x,
            y,
            height,
            colour.r,
            colour.g,
            colour.b,
            colour.a,
            brightness);
}

void draw_text_centred(
    SDL_Renderer* renderer,
    std::string_view text,
    const NativeRect& area,
    float pixel,
    NativeColour colour,
    std::uint8_t brightness) noexcept {

    const auto width =
        text_width(
            text,
            pixel);


    draw_text(
        renderer,
        text,
        area.x
            + (
                area.w
                - width
              ) * 0.5F,
        area.y
            + (
                area.h
                - 7.0F * pixel
              ) * 0.5F,
        pixel,
        colour,
        brightness);
}


NativeRect fit_rect(
    float source_width,
    float source_height,
    const NativeRect& destination) noexcept {

    if (source_width <= 0.0F
        || source_height <= 0.0F) {

        return destination;
    }


    const auto scale =
        std::min(
            destination.w
                / source_width,
            destination.h
                / source_height);


    const auto width =
        source_width
        * scale;

    const auto height =
        source_height
        * scale;


    return {
        destination.x
            + (
                destination.w
                - width
              ) * 0.5F,

        destination.y
            + (
                destination.h
                - height
              ) * 0.5F,

        width,
        height
    };
}


std::string_view select_name(
    ControlVisualProfile profile) noexcept {

    switch (profile) {

    case ControlVisualProfile::dualshock4:
    case ControlVisualProfile::dualsense:
        return "SHARE";

    case ControlVisualProfile::xbox:
        return "VIEW";

    case ControlVisualProfile::switch_single_joycon:
        return "STICK";

    case ControlVisualProfile::switch_pro_controller:
    case ControlVisualProfile::switch_dual_joycon:
    case ControlVisualProfile::switch_handheld:
        return "-";

    case ControlVisualProfile::keyboard_pc:
        return "SELECT";

    default:
        return "SELECT";
    }
}


std::string_view start_name(
    ControlVisualProfile profile) noexcept {

    switch (profile) {

    case ControlVisualProfile::dualshock4:
    case ControlVisualProfile::dualsense:
        return "OPTIONS";

    case ControlVisualProfile::xbox:
        return "MENU";

    case ControlVisualProfile::switch_single_joycon:
        return "+/-";

    case ControlVisualProfile::switch_pro_controller:
    case ControlVisualProfile::switch_dual_joycon:
    case ControlVisualProfile::switch_handheld:
        return "+";

    case ControlVisualProfile::keyboard_pc:
        return "ENTER";

    default:
        return "START";
    }
}

} // namespace


bool render_native_controls_ui(
    SDL_Renderer* renderer,
    SDL_Texture* cartridge_texture,
    std::uint32_t cartridge_width,
    std::uint32_t cartridge_height,
    SDL_Texture* controller_texture,
    const SDL_FRect& controller_source,
    const NativeControlsUiModel& model) noexcept {

    if (renderer == nullptr
        || cartridge_texture == nullptr
        || controller_texture == nullptr) {

        return false;
    }


    int output_width{};
    int output_height{};


    if (!SDL_GetCurrentRenderOutputSize(
            renderer,
            &output_width,
            &output_height)
        || output_width <= 0
        || output_height <= 0) {

        return false;
    }


    // Native UI explicitly bypasses the SNES logical resolution.
    if (!SDL_SetRenderLogicalPresentation(
            renderer,
            0,
            0,
            SDL_LOGICAL_PRESENTATION_DISABLED)) {

        return false;
    }


    const auto brightness =
        std::min<std::uint8_t>(
            model.brightness,
            15U);


    constexpr NativeColour background{
        35U,
        55U,
        73U,
        255U
    };

    constexpr NativeColour panel{
        23U,
        38U,
        53U,
        255U
    };

    constexpr NativeColour panel_light{
        51U,
        73U,
        91U,
        255U
    };

    constexpr NativeColour white{
        245U,
        248U,
        246U,
        255U
    };

    constexpr NativeColour cyan{
        137U,
        249U,
        241U,
        255U
    };

    constexpr NativeColour dim{
        126U,
        139U,
        151U,
        255U
    };

    constexpr NativeColour yellow{
        255U,
        190U,
        21U,
        255U
    };


    set_colour(
        renderer,
        background,
        brightness);

    static_cast<void>(
        SDL_RenderClear(
            renderer));


    // --------------------------------------------------------
    // Safe 16:9 design canvas.
    //
    // The outer monitor may be 4:3, 16:10, 21:9, 32:9, etc.
    // UI positions are derived from this safe area rather than
    // from SNES pixels.
    // --------------------------------------------------------

    const auto output_aspect =
        static_cast<float>(
            output_width)
        / static_cast<float>(
            output_height);


    constexpr float design_aspect =
        16.0F / 9.0F;


    float safe_width =
        static_cast<float>(
            output_width);

    float safe_height =
        static_cast<float>(
            output_height);


    if (output_aspect > design_aspect) {

        safe_width =
            safe_height
            * design_aspect;

    } else {

        safe_height =
            safe_width
            / design_aspect;
    }


    const auto safe_x =
        (
            static_cast<float>(
                output_width)
            - safe_width
        ) * 0.5F;


    const auto safe_y =
        (
            static_cast<float>(
                output_height)
            - safe_height
        ) * 0.5F;


    const auto scale =
        safe_height
        / 720.0F;


    const auto X =
        [safe_x, scale](
            float value) {

            return safe_x
                + value * scale;
        };


    const auto Y =
        [safe_y, scale](
            float value) {

            return safe_y
                + value * scale;
        };


    const auto S =
        [scale](
            float value) {

            return value
                * scale;
        };


    // --------------------------------------------------------
    // LEFT SIDE
    // --------------------------------------------------------

    const NativeRect preview_panel{
        X(48.0F),
        Y(54.0F),
        S(660.0F),
        S(338.0F)
    };


    fill_rect(
        renderer,
        preview_panel,
        panel,
        brightness);


    stroke_rect(
        renderer,
        preview_panel,
        std::max(
            2.0F,
            S(4.0F)),
        white,
        brightness);


    const NativeRect preview_inner{
        preview_panel.x
            + S(14.0F),
        preview_panel.y
            + S(14.0F),
        preview_panel.w
            - S(28.0F),
        preview_panel.h
            - S(28.0F)
    };


    fill_rect(
        renderer,
        preview_inner,
        {0U, 0U, 0U, 255U},
        brightness);


    // Use only CONT.SCR's animated flight window interior.
    const auto viewport_origin =
        cartridge_width > 256U
        ? (
            cartridge_width
            - 256U
          ) / 2U
        : 0U;


    const SDL_FRect arwing_source{
        static_cast<float>(
            viewport_origin
            + 26U),
        26.0F,
        108.0F,
        92.0F
    };


    const auto preview_output =
        fit_rect(
            arwing_source.w,
            arwing_source.h,
            preview_inner);


    // STARFOX_NATIVE_UI_GAME_PREVIEW_PASS05
    //
    // Enlarge the cartridge-driven Arwing preview without
    // depending on the exact SNES source crop.

    constexpr float preview_zoom =
        1.42F;


    const auto preview_width =
        preview_output.w
        * preview_zoom;


    const auto preview_height =
        preview_output.h
        * preview_zoom;


    const SDL_FRect preview_destination{

        preview_inner.x
            + (
                preview_inner.w
                - preview_width
              ) * 0.5F,

        preview_inner.y
            + (
                preview_inner.h
                - preview_height
              ) * 0.40F
            - S(10.0F),

        preview_width,
        preview_height
    };


    const auto texture_brightness =
        static_cast<std::uint8_t>(
            (
                static_cast<unsigned>(
                    brightness)
                * 255U
            ) / 15U);


    static_cast<void>(
        SDL_SetTextureColorMod(
            cartridge_texture,
            texture_brightness,
            texture_brightness,
            texture_brightness));


    // STARFOX_NATIVE_UI_PREVIEW_FILTER_PASS05
    //
    // Smooth and clip only the remastered preview.
    // Gameplay is immediately restored to NEAREST.

    const SDL_Rect preview_clip{
        static_cast<int>(
            std::floor(
                preview_inner.x)),

        static_cast<int>(
            std::floor(
                preview_inner.y)),

        static_cast<int>(
            std::ceil(
                preview_inner.w)),

        static_cast<int>(
            std::ceil(
                preview_inner.h))
    };


    static_cast<void>(
        SDL_SetRenderClipRect(
            renderer,
            &preview_clip));


    static_cast<void>(
        SDL_SetTextureScaleMode(
            cartridge_texture,
            SDL_SCALEMODE_LINEAR));


    static_cast<void>(
        SDL_RenderTexture(
            renderer,
            cartridge_texture,
            &arwing_source,
            &preview_destination));


    static_cast<void>(
        SDL_SetTextureScaleMode(
            cartridge_texture,
            SDL_SCALEMODE_NEAREST));


    static_cast<void>(
        SDL_SetRenderClipRect(
            renderer,
            nullptr));


    static_cast<void>(
        SDL_SetTextureColorMod(
            cartridge_texture,
            255U,
            255U,
            255U));


    // Controller area.
    const NativeRect controller_panel{
        X(48.0F),
        Y(410.0F),
        S(660.0F),
        S(264.0F)
    };


    fill_rect(
        renderer,
        controller_panel,
        panel,
        brightness);


    stroke_rect(
        renderer,
        controller_panel,
        std::max(
            2.0F,
            S(2.0F)),
        panel_light,
        brightness);


    const NativeRect controller_inner{
        controller_panel.x
            + S(16.0F),
        controller_panel.y
            + S(10.0F),
        controller_panel.w
            - S(32.0F),
        controller_panel.h
            - S(20.0F)
    };


    const auto controller_output =
        fit_rect(
            controller_source.w,
            controller_source.h,
            controller_inner);


    const SDL_FRect controller_destination{
        controller_output.x,
        controller_output.y,
        controller_output.w,
        controller_output.h
    };


    static_cast<void>(
        SDL_SetTextureColorMod(
            controller_texture,
            texture_brightness,
            texture_brightness,
            texture_brightness));


    static_cast<void>(
        SDL_SetTextureAlphaMod(
            controller_texture,
            texture_brightness));


    static_cast<void>(
        SDL_RenderTexture(
            renderer,
            controller_texture,
            &controller_source,
            &controller_destination));


    static_cast<void>(
        SDL_SetTextureColorMod(
            controller_texture,
            255U,
            255U,
            255U));


    static_cast<void>(
        SDL_SetTextureAlphaMod(
            controller_texture,
            255U));


    // --------------------------------------------------------
    // RIGHT SIDE
    // --------------------------------------------------------

    const NativeRect right_panel{
        X(744.0F),
        Y(54.0F),
        S(488.0F),
        S(620.0F)
    };


    fill_rect(
        renderer,
        right_panel,
        panel,
        brightness);


    stroke_rect(
        renderer,
        right_panel,
        std::max(
            2.0F,
            S(2.0F)),
        panel_light,
        brightness);


    // STARFOX_NATIVE_UI_CONTROLS_CHOICE_PASS06
    //
    // model.control_type:
    //
    // 0..3 = CONTROL A/B/C/D page
    // 4    = TRAINING
    // 5    = GAME
    //
    // The underlying GameSimulation remains authoritative;
    // this branch only replaces presentation.

    const auto choice_page =
        model.control_type >= 4U
        && model.control_type <= 5U;


    if (choice_page) {

        const auto choice =
            static_cast<std::uint8_t>(
                model.control_type
                - 4U);


        // ----------------------------------------------------
        // TITLE
        // ----------------------------------------------------

        draw_text_centred(
            renderer,
            "SELECT MODE",
            {
                X(764.0F),
                Y(78.0F),
                S(448.0F),
                S(72.0F)
            },
            std::max(
                2.0F,
                S(5.1F)),
            white,
            brightness);


        draw_text_centred(
            renderer,
            "CHOOSE YOUR NEXT MISSION",
            {
                X(764.0F),
                Y(149.0F),
                S(448.0F),
                S(42.0F)
            },
            std::max(
                2.0F,
                S(2.4F)),
            cyan,
            brightness);


        // ----------------------------------------------------
        // TRAINING / GAME
        // ----------------------------------------------------

        constexpr std::array<
            std::string_view,
            2> mode_names{
                "TRAINING",
                "GAME"
            };


        for (std::size_t index = 0U;
             index < mode_names.size();
             ++index) {

            const auto selected =
                static_cast<std::uint8_t>(
                    index)
                == choice;


            const NativeRect row{
                X(812.0F),

                Y(
                    248.0F
                    + static_cast<float>(
                        index)
                    * 112.0F),

                S(352.0F),
                S(76.0F)
            };


            fill_rect(
                renderer,
                row,

                selected

                    ? NativeColour{
                        64U,
                        88U,
                        105U,
                        255U}

                    : NativeColour{
                        41U,
                        49U,
                        60U,
                        255U},

                brightness);


            stroke_rect(
                renderer,
                row,

                std::max(
                    2.0F,
                    S(2.0F)),

                selected
                    ? cyan
                    : dim,

                brightness);


            draw_text_centred(
                renderer,
                mode_names[index],
                row,

                std::max(
                    2.0F,
                    S(4.0F)),

                selected
                    ? cyan
                    : dim,

                brightness);


            if (selected) {

                const NativeRect marker{
                    X(776.0F),

                    row.y
                        + row.h
                            * 0.5F
                        - S(9.0F),

                    S(18.0F),
                    S(18.0F)
                };


                fill_rect(
                    renderer,
                    marker,
                    yellow,
                    brightness);
            }
        }


        // ----------------------------------------------------
        // HELP
        // ----------------------------------------------------

        draw_text_centred(
            renderer,
            "UP / DOWN / CHANGE VIEW",
            {
                X(764.0F),
                Y(502.0F),
                S(448.0F),
                S(42.0F)
            },

            std::max(
                2.0F,
                S(2.4F)),

            cyan,
            brightness);


        draw_text_centred(
            renderer,
            "FIRE / START TO CONFIRM",
            {
                X(744.0F),
                Y(558.0F),
                S(488.0F),
                S(44.0F)
            },

            std::max(
                2.0F,
                S(2.25F)),

            white,
            brightness);


        draw_text_centred(
            renderer,
            "BOOST TO BACK",
            {
                X(744.0F),
                Y(613.0F),
                S(488.0F),
                S(32.0F)
            },

            std::max(
                1.5F,
                S(1.85F)),

            dim,
            brightness);


        return true;
    }


    draw_text_centred(
        renderer,
        "CONTROLS",
        {
            X(764.0F),
            Y(74.0F),
            S(448.0F),
            S(72.0F)
        },
        std::max(
            3.0F,
            S(6.0F)),
        white,
        brightness);


    const std::string top_prompt =
        std::string{"PUSH "}
        + std::string{
            select_name(
                model.profile)};


    draw_text_centred(
        renderer,
        top_prompt,
        {
            X(764.0F),
            Y(140.0F),
            S(448.0F),
            S(52.0F)
        },
        std::max(
            2.0F,
            S(3.5F)),
        cyan,
        brightness);


    // --------------------------------------------------------
    // CONTROL A/B/C/D
    // --------------------------------------------------------

    constexpr std::array<
        std::string_view,
        4> names{
            "CONTROL A",
            "CONTROL B",
            "CONTROL C",
            "CONTROL D"
        };


    for (std::size_t index = 0U;
         index < names.size();
         ++index) {

        const auto selected =
            index
            == (
                model.control_type
                & 3U
            );


        const NativeRect row{
            X(812.0F),
            Y(
                216.0F
                + static_cast<float>(
                    index)
                * 74.0F),
            S(352.0F),
            S(58.0F)
        };


        fill_rect(
            renderer,
            row,
            selected
                ? NativeColour{
                    64U,
                    88U,
                    105U,
                    255U}
                : NativeColour{
                    41U,
                    49U,
                    60U,
                    255U},
            brightness);


        stroke_rect(
            renderer,
            row,
            std::max(
                2.0F,
                S(2.0F)),
            selected
                ? cyan
                : dim,
            brightness);


        draw_text_centred(
            renderer,
            names[index],
            row,
            std::max(
                2.0F,
                S(3.6F)),
            selected
                ? cyan
                : dim,
            brightness);


        if (selected) {

            const NativeRect arrow{
                X(776.0F),
                row.y
                    + row.h * 0.5F
                    - S(8.0F),
                S(18.0F),
                S(16.0F)
            };


            fill_rect(
                renderer,
                arrow,
                yellow,
                brightness);
        }
    }


    const std::string footer =
        std::string{"PUSH "}
        + std::string{
            start_name(
                model.profile)};


    draw_text_centred(
        renderer,
        footer,
        {
            X(764.0F),
            Y(536.0F),
            S(448.0F),
            S(54.0F)
        },
        std::max(
            2.0F,
            S(3.5F)),
        cyan,
        brightness);


    draw_text_centred(
        renderer,
        "TO EXIT",
        {
            X(764.0F),
            Y(590.0F),
            S(448.0F),
            S(48.0F)
        },
        std::max(
            2.0F,
            S(3.5F)),
        cyan,
        brightness);


    return true;
}


// STARFOX_NATIVE_TITLE_UI_IMPLEMENTATION_PASS07

bool render_native_title_ui(
    SDL_Renderer* renderer,
    SDL_Texture* cartridge_texture,
    std::uint32_t cartridge_width,
    std::uint32_t cartridge_height,
    std::span<const std::uint8_t> rgba_pixels,
    std::uint8_t brightness) noexcept {

    static_cast<void>(rgba_pixels);

    if (renderer == nullptr
        || cartridge_texture == nullptr
        || cartridge_width == 0U
        || cartridge_height == 0U) {

        return false;
    }

    int output_width{};
    int output_height{};

    if (!SDL_GetCurrentRenderOutputSize(
            renderer,
            &output_width,
            &output_height)
        || output_width <= 0
        || output_height <= 0) {

        return false;
    }

    if (!SDL_SetRenderLogicalPresentation(
            renderer,
            0,
            0,
            SDL_LOGICAL_PRESENTATION_DISABLED)) {

        return false;
    }

    const auto source_width =
        static_cast<float>(cartridge_width);
    const auto source_height =
        static_cast<float>(cartridge_height);
    const auto target_width =
        static_cast<float>(output_width);
    const auto target_height =
        static_cast<float>(output_height);

    const auto scale =
        std::max(
            target_width / source_width,
            target_height / source_height);

    const SDL_FRect source{
        0.0F,
        0.0F,
        source_width,
        source_height
    };

    const SDL_FRect destination{
        (target_width - source_width * scale) * 0.5F,
        (target_height - source_height * scale) * 0.5F,
        source_width * scale,
        source_height * scale
    };

    brightness =
        std::min<std::uint8_t>(
            brightness,
            15U);

    const auto colour =
        static_cast<std::uint8_t>(
            static_cast<unsigned>(brightness)
            * 255U / 15U);

    static_cast<void>(
        SDL_SetTextureColorMod(
            cartridge_texture,
            colour,
            colour,
            colour));

    static_cast<void>(
        SDL_SetTextureScaleMode(
            cartridge_texture,
            SDL_SCALEMODE_NEAREST));

    static_cast<void>(
        SDL_SetRenderDrawColor(
            renderer,
            0U,
            0U,
            0U,
            255U));

    static_cast<void>(
        SDL_RenderClear(renderer));

    const auto rendered =
        SDL_RenderTexture(
            renderer,
            cartridge_texture,
            &source,
            &destination);

    static_cast<void>(
        SDL_SetTextureColorMod(
            cartridge_texture,
            255U,
            255U,
            255U));

    return rendered;
}


} // namespace starfox::app
