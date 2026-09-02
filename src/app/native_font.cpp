#include "starfox/app/native_font.hpp"

#include <ft2build.h>
#include FT_FREETYPE_H

#include <SDL3/SDL.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace starfox::app {
namespace {

struct GlyphKey {
    std::uint32_t pixel_height{};
    std::uint32_t codepoint{};

    [[nodiscard]]
    bool operator==(
        const GlyphKey&) const noexcept = default;
};


struct GlyphKeyHash {
    [[nodiscard]]
    std::size_t operator()(
        const GlyphKey& key) const noexcept {

        return (
            static_cast<std::size_t>(
                key.pixel_height)
            << 32U
        ) ^ static_cast<std::size_t>(
            key.codepoint);
    }
};


struct Glyph {
    SDL_Texture* texture{};

    int bitmap_width{};
    int bitmap_height{};

    int bearing_x{};
    int bearing_y{};

    float advance{};
};


struct NativeFontState {
    FT_Library library{};
    FT_Face face{};

    SDL_Renderer* renderer{};

    std::uint32_t current_pixel_height{};

    bool initialized{};
    bool load_attempted{};

    std::unordered_map<
        GlyphKey,
        Glyph,
        GlyphKeyHash>
        glyphs;
};


NativeFontState& state() noexcept {

    static NativeFontState value;

    return value;
}


void destroy_glyph_textures(
    NativeFontState& value) noexcept {

    for (auto& [key, glyph] :
         value.glyphs) {

        static_cast<void>(key);

        SDL_DestroyTexture(
            glyph.texture);

        glyph.texture =
            nullptr;
    }


    value.glyphs.clear();
}


std::vector<std::filesystem::path>
font_candidates() {

    std::vector<
        std::filesystem::path>
        candidates;


#if defined(STARFOX_SWITCH_RUNTIME)

    candidates.emplace_back(
        "romfs:/ui/DejaVuSans.ttf");

#else

    candidates.emplace_back(
        std::filesystem::current_path()
        / "assets/ui/DejaVuSans.ttf");


    if (const auto* base =
            SDL_GetBasePath();
        base != nullptr) {

        const auto executable =
            std::filesystem::path{
                base};


        candidates.emplace_back(
            executable
            / "assets/ui/DejaVuSans.ttf");


        candidates.emplace_back(
            executable
                .parent_path()
                .parent_path()
            / "assets/ui/DejaVuSans.ttf");
    }

#endif


    return candidates;
}


bool ensure_face() noexcept {

    auto& value =
        state();


    if (value.face != nullptr) {
        return true;
    }


    if (value.load_attempted) {
        return false;
    }


    value.load_attempted =
        true;


    if (FT_Init_FreeType(
            &value.library)
        != 0) {

        return false;
    }


    for (const auto& candidate :
         font_candidates()) {

        if (FT_New_Face(
                value.library,
                candidate
                    .string()
                    .c_str(),
                0,
                &value.face)
            == 0) {

            value.initialized =
                true;

            return true;
        }
    }


    FT_Done_FreeType(
        value.library);

    value.library =
        nullptr;


    return false;
}


std::uint32_t normalize_height(
    float pixel_height) noexcept {

    return static_cast<std::uint32_t>(
        std::clamp(
            std::lround(
                pixel_height),
            8L,
            192L));
}


bool set_height(
    std::uint32_t pixel_height) noexcept {

    auto& value =
        state();


    if (!ensure_face()) {
        return false;
    }


    if (value.current_pixel_height
        == pixel_height) {

        return true;
    }


    if (FT_Set_Pixel_Sizes(
            value.face,
            0U,
            pixel_height)
        != 0) {

        return false;
    }


    value.current_pixel_height =
        pixel_height;


    return true;
}


std::uint8_t bitmap_alpha(
    const FT_Bitmap& bitmap,
    int x,
    int y) noexcept {

    if (x < 0
        || y < 0
        || x >= static_cast<int>(
            bitmap.width)
        || y >= static_cast<int>(
            bitmap.rows)) {

        return 0U;
    }


    const auto pitch =
        bitmap.pitch;


    const auto* row =
        pitch >= 0

        ? bitmap.buffer
            + y * pitch

        : bitmap.buffer
            + (
                static_cast<int>(
                    bitmap.rows)
                - 1
                - y
              )
              * (-pitch);


    if (bitmap.pixel_mode
        == FT_PIXEL_MODE_MONO) {

        const auto byte =
            row[x >> 3];

        const auto bit =
            static_cast<unsigned>(
                7
                - (x & 7));


        return (
            byte
            & (
                1U
                << bit
            )
        )
            ? 255U
            : 0U;
    }


    return row[x];
}


Glyph create_glyph(
    SDL_Renderer* renderer,
    std::uint32_t pixel_height,
    std::uint32_t codepoint) noexcept {

    Glyph result{};


    auto& value =
        state();


    if (!set_height(
            pixel_height)) {

        return result;
    }


    if (FT_Load_Char(
            value.face,
            codepoint,
            FT_LOAD_RENDER
                | FT_LOAD_TARGET_NORMAL)
        != 0) {

        return result;
    }


    const auto* slot =
        value.face->glyph;


    result.bitmap_width =
        static_cast<int>(
            slot->bitmap.width);

    result.bitmap_height =
        static_cast<int>(
            slot->bitmap.rows);

    result.bearing_x =
        slot->bitmap_left;

    result.bearing_y =
        slot->bitmap_top;

    result.advance =
        static_cast<float>(
            slot->advance.x)
        / 64.0F;


    if (result.bitmap_width <= 0
        || result.bitmap_height <= 0) {

        return result;
    }


    std::vector<std::uint8_t>
        pixels(
            static_cast<std::size_t>(
                result.bitmap_width)
            * result.bitmap_height
            * 4U,
            0U);


    for (int y = 0;
         y < result.bitmap_height;
         ++y) {

        for (int x = 0;
             x < result.bitmap_width;
             ++x) {

            const auto alpha =
                bitmap_alpha(
                    slot->bitmap,
                    x,
                    y);


            const auto offset =
                (
                    static_cast<std::size_t>(
                        y)
                    * result.bitmap_width
                    + x
                ) * 4U;


            pixels[offset] =
                255U;

            pixels[offset + 1U] =
                255U;

            pixels[offset + 2U] =
                255U;

            pixels[offset + 3U] =
                alpha;
        }
    }


    result.texture =
        SDL_CreateTexture(
            renderer,
            SDL_PIXELFORMAT_RGBA32,
            SDL_TEXTUREACCESS_STATIC,
            result.bitmap_width,
            result.bitmap_height);


    if (result.texture == nullptr) {

        return result;
    }


    if (!SDL_UpdateTexture(
            result.texture,
            nullptr,
            pixels.data(),
            result.bitmap_width
                * 4)) {

        SDL_DestroyTexture(
            result.texture);

        result.texture =
            nullptr;

        return result;
    }


    static_cast<void>(
        SDL_SetTextureBlendMode(
            result.texture,
            SDL_BLENDMODE_BLEND));


    static_cast<void>(
        SDL_SetTextureScaleMode(
            result.texture,
            SDL_SCALEMODE_LINEAR));


    return result;
}


Glyph* glyph_for(
    SDL_Renderer* renderer,
    std::uint32_t pixel_height,
    std::uint32_t codepoint) noexcept {

    auto& value =
        state();


    if (value.renderer
        != renderer) {

        destroy_glyph_textures(
            value);

        value.renderer =
            renderer;
    }


    const GlyphKey key{
        pixel_height,
        codepoint
    };


    if (const auto found =
            value.glyphs.find(
                key);
        found != value.glyphs.end()) {

        return &found->second;
    }


    auto glyph =
        create_glyph(
            renderer,
            pixel_height,
            codepoint);


    auto [entry, inserted] =
        value.glyphs.emplace(
            key,
            std::move(
                glyph));


    static_cast<void>(
        inserted);


    return &entry->second;
}


float ascender_for(
    std::uint32_t pixel_height) noexcept {

    auto& value =
        state();


    if (!set_height(
            pixel_height)) {

        return static_cast<float>(
            pixel_height)
            * 0.8F;
    }


    return static_cast<float>(
        value.face
            ->size
            ->metrics
            .ascender)
        / 64.0F;
}


void draw_glyph_texture(
    SDL_Renderer* renderer,
    Glyph& glyph,
    float x,
    float y,
    std::uint8_t red,
    std::uint8_t green,
    std::uint8_t blue,
    std::uint8_t alpha) noexcept {

    if (glyph.texture == nullptr) {
        return;
    }


    static_cast<void>(
        SDL_SetTextureColorMod(
            glyph.texture,
            red,
            green,
            blue));


    static_cast<void>(
        SDL_SetTextureAlphaMod(
            glyph.texture,
            alpha));


    const SDL_FRect destination{
        x,
        y,
        static_cast<float>(
            glyph.bitmap_width),
        static_cast<float>(
            glyph.bitmap_height)
    };


    static_cast<void>(
        SDL_RenderTexture(
            renderer,
            glyph.texture,
            nullptr,
            &destination));
}


std::uint8_t faded_component(
    std::uint8_t value,
    std::uint8_t brightness) noexcept {

    brightness =
        std::min<std::uint8_t>(
            brightness,
            15U);


    return static_cast<std::uint8_t>(
        (
            static_cast<unsigned>(
                value)
            * brightness
        ) / 15U);
}

} // namespace


float measure_native_ui_text(
    std::string_view text,
    float pixel_height) noexcept {

    if (text.empty()) {
        return 0.0F;
    }


    const auto height =
        normalize_height(
            pixel_height);


    auto& value =
        state();


    if (!set_height(
            height)) {

        return static_cast<float>(
            text.size())
            * pixel_height
            * 0.58F;
    }


    float width{};


    for (const auto character :
         text) {

        if (FT_Load_Char(
                value.face,
                static_cast<unsigned char>(
                    character),
                FT_LOAD_DEFAULT)
            != 0) {

            width +=
                pixel_height
                * 0.58F;

            continue;
        }


        width +=
            static_cast<float>(
                value.face
                    ->glyph
                    ->advance.x)
            / 64.0F;
    }


    return width;
}


void draw_native_ui_text(
    SDL_Renderer* renderer,
    std::string_view text,
    float x,
    float y,
    float pixel_height,
    std::uint8_t red,
    std::uint8_t green,
    std::uint8_t blue,
    std::uint8_t alpha,
    std::uint8_t brightness) noexcept {

    if (renderer == nullptr
        || text.empty()) {

        return;
    }


    const auto height =
        normalize_height(
            pixel_height);


    const auto ascender =
        ascender_for(
            height);


    const auto baseline =
        y
        + ascender;


    const auto final_red =
        faded_component(
            red,
            brightness);

    const auto final_green =
        faded_component(
            green,
            brightness);

    const auto final_blue =
        faded_component(
            blue,
            brightness);


    auto pen_x =
        x;


    const auto shadow_offset =
        std::max(
            1.0F,
            pixel_height
                * 0.025F);


    for (const auto character :
         text) {

        auto* glyph =
            glyph_for(
                renderer,
                height,
                static_cast<unsigned char>(
                    character));


        if (glyph == nullptr) {

            pen_x +=
                pixel_height
                * 0.58F;

            continue;
        }


        if (glyph->texture
            != nullptr) {

            const auto glyph_x =
                pen_x
                + static_cast<float>(
                    glyph->bearing_x);


            const auto glyph_y =
                baseline
                - static_cast<float>(
                    glyph->bearing_y);


            // Subtle professional shadow.
            draw_glyph_texture(
                renderer,
                *glyph,
                glyph_x
                    + shadow_offset,
                glyph_y
                    + shadow_offset,
                0U,
                0U,
                0U,
                static_cast<std::uint8_t>(
                    alpha / 3U));


            draw_glyph_texture(
                renderer,
                *glyph,
                glyph_x,
                glyph_y,
                final_red,
                final_green,
                final_blue,
                alpha);
        }


        pen_x +=
            glyph->advance;
    }
}


void shutdown_native_ui_font(
    SDL_Renderer* renderer) noexcept {

    auto& value =
        state();


    if (value.renderer
        != renderer) {

        return;
    }


    destroy_glyph_textures(
        value);


    if (value.face != nullptr) {

        FT_Done_Face(
            value.face);

        value.face =
            nullptr;
    }


    if (value.library != nullptr) {

        FT_Done_FreeType(
            value.library);

        value.library =
            nullptr;
    }


    value.renderer =
        nullptr;

    value.current_pixel_height =
        0U;

    value.initialized =
        false;

    value.load_attempted =
        false;
}

} // namespace starfox::app
