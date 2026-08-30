#include "starfox/app/perf_profiler.hpp"
#include "starfox/render/scaled_text_renderer.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <stdexcept>
#include <string>
#include <vector>
#include <utility>

namespace starfox::render {
namespace {

std::uint32_t rom_symbol(
    const assets::SymbolMap& symbols,
    const std::string& name) {
    for (const auto address : symbols.find(name)) {
        if ((address & 0xffffU) >= 0x8000U
            && ((address >> 16U) & 0xffU) < 0x70U) {
            return address;
        }
    }
    throw std::runtime_error{"missing scaled-text ROM symbol: " + name};
}

} // namespace

ScaledTextRenderer::ScaledTextRenderer(
    const assets::RomImage& rom,
    const assets::SymbolMap& symbols)
    : rom_(&rom),
      font_(rom_symbol(symbols, "MSCALECHARS")),
      messages_(rom_symbol(symbols, "MARIOMSGS")),
      game_font_widths_(rom_symbol(symbols, "FONT0WID")),
      game_font_glyphs_(rom_symbol(symbols, "FONT0FON")),
      game_font_translation_(rom_symbol(symbols, "FONT0TRN")),
      face_data_(rom_symbol(symbols, "FACEDATA")) {
    for (const auto address : symbols.find("FACEDATA2")) {
        if ((address & 0xffffU) >= 0x8000U
            && ((address >> 16U) & 0xffU) < 0x70U) {
            face_data_2_ = address;
            break;
        }
    }
}

void ScaledTextRenderer::draw(
    std::uint16_t message_pointer,
    std::uint8_t colour,
    std::int8_t size_adjustment,
    const RenderPose& pose,
    Framebuffer& target,
    std::uint8_t colour_index_base) const {
    starfox::app::perf::ScopedTimer
        perf_timer_text_draw{
            starfox::app::perf::Bucket::text};

    // A text object may remain in the object list for one update before its
    // message pointer is assigned (Star Fox EX does this during its intro).
    // The Super FX sees the lower half of a LoROM bank as non-ROM/open bus;
    // it is not a valid projected-message string.  Treat that transient state
    // as invisible instead of asking RomImage to translate e.g. $2d:0000.
    if (pose.z < 128.0 || message_pointer < 0x8000U) return;
    const auto message_address = (messages_ & 0xff0000U) | message_pointer;
    std::vector<std::uint8_t> characters;
    characters.reserve(32U);
    for (std::uint32_t index = 0; index < 256U; ++index) {
        const auto character = rom_->read8(message_address + index);
        if (character == 0U) break;
        characters.push_back(character);
    }
    if (characters.empty()) return;

    constexpr double focal_length = 256.0;
    const auto world_character_size = 127 + static_cast<int>(size_adjustment);
    if (world_character_size <= 0) return;
    const auto dimension = static_cast<int>(std::trunc(
        world_character_size * focal_length / pose.z));
    if (dimension <= 0) return;
    const auto centre_x = static_cast<int>(target.width() / 2U) + static_cast<int>(
        std::trunc(pose.x * focal_length / pose.z));
    const auto centre_y = static_cast<int>(target.height() / 2U) + static_cast<int>(
        std::trunc(pose.y * focal_length / pose.z));
    const auto string_width = dimension * static_cast<int>(characters.size());
    const auto left = centre_x - string_width / 2;
    const auto top = centre_y - dimension / 2;
    const auto output_colour = static_cast<std::uint8_t>(colour_index_base + colour);

    for (std::size_t character_index = 0;
         character_index < characters.size(); ++character_index) {
        const auto token = characters[character_index];
        if (token == 0U || token > 41U) continue;
        const auto glyph = font_ + static_cast<std::uint32_t>(token - 1U) * 32U;
        for (auto y = 0; y < dimension; ++y) {
            const auto source_y = std::min(15, y * 16 / dimension);
            const auto row = rom_->read16(glyph + static_cast<std::uint32_t>(source_y * 2));
            for (auto x = 0; x < dimension; ++x) {
                const auto source_x = std::min(15, x * 16 / dimension);
                if ((row & (0x8000U >> source_x)) == 0U) continue;
                target.set(left + static_cast<int>(character_index) * dimension + x,
                    top + y, output_colour);
            }
        }
    }
}

void ScaledTextRenderer::draw_game_text(
    std::uint32_t text_address,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour_index_base,
    std::optional<std::uint8_t> forced_colour,
    std::int32_t right_clip,
    std::size_t max_characters) const {
    starfox::app::perf::ScopedTimer
        perf_timer_text_game{
            starfox::app::perf::Bucket::text};

    // EX can open the portrait/message window one source update before it
    // assigns FRIENDS_MESSAGE. dialogue_state() retains MARIOMSGS' bank, so
    // that transient null pointer arrives here as e.g. $2d:0000 instead of
    // integer zero. The SNES sees open bus in the lower half of a LoROM bank;
    // it does not try to read a string there.
    if ((text_address & 0xffffU) < 0x8000U) return;
    const auto colour = rom_->read8(text_address++);
    const auto output_colour = static_cast<std::uint8_t>(
        colour_index_base + (forced_colour.value_or(colour) & 0x0fU));
    std::vector<std::uint8_t> text;
    text.reserve(256U);
    for (std::size_t character = 0;
         character < std::min<std::size_t>(256U, max_characters); ++character) {
        const auto ascii = rom_->read8(text_address + character);
        if (ascii == 0U) break;
        text.push_back(ascii);
    }
    const auto glyph_width = [this](std::uint8_t ascii) {
        if (ascii == 32U) return std::uint8_t{5U};
        if (ascii < 32U) return std::uint8_t{};
        const auto translated = rom_->read8(
            game_font_translation_ + static_cast<std::uint32_t>(ascii - 32U));
        return rom_->read8(game_font_widths_ + translated);
    };
    const auto draw_character = [this, &target, output_colour, &glyph_width](
                                    std::uint8_t ascii,
                                    std::int32_t draw_x,
                                    std::int32_t draw_y) {
        const auto width = glyph_width(ascii);
        if (ascii <= 32U || width == 0U) return;
        const auto translated = rom_->read8(
            game_font_translation_ + static_cast<std::uint32_t>(ascii - 32U));
        const auto glyph = game_font_glyphs_
            + static_cast<std::uint32_t>(translated) * 24U;
        for (std::int32_t row = 0; row < 12; ++row) {
            const auto bits = rom_->read16(glyph + static_cast<std::uint32_t>(row * 2));
            for (std::int32_t column = 0; column < width; ++column) {
                if ((bits & (0x8000U >> column)) != 0U) {
                    target.set(draw_x + column, draw_y + row, output_colour);
                }
            }
        }
    };

    std::size_t line_start = 0U;
    while (line_start < text.size() && y < static_cast<std::int32_t>(target.height())) {
        auto line_end = text.size();
        auto next_line = text.size();
        std::size_t last_space = text.size();
        std::int32_t line_width = 0;
        for (std::size_t index = line_start; index < text.size(); ++index) {
            const auto width = static_cast<std::int32_t>(glyph_width(text[index]));
            if (text[index] == 32U) last_space = index;
            if (x + line_width + width > right_clip) {
                if (last_space != text.size() && last_space >= line_start) {
                    line_end = last_space;
                    next_line = last_space + 1U;
                } else {
                    line_end = index;
                    next_line = index;
                }
                break;
            }
            line_width += width;
        }

        auto draw_x = x;
        for (auto index = line_start; index < line_end; ++index) {
            draw_character(text[index], draw_x, y);
            draw_x += glyph_width(text[index]);
        }
        if (next_line == text.size()) break;
        if (next_line <= line_start) ++next_line;
        line_start = next_line;
        y += 13;
    }
}

void ScaledTextRenderer::draw_face(
    std::uint8_t frame,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour_index_base,
    bool alternate_portraits) const {
    starfox::app::perf::ScopedTimer
        perf_timer_text_face{
            starfox::app::perf::Bucket::text};

    const auto data = alternate_portraits && face_data_2_ != 0U
        ? face_data_2_ : face_data_;
    const auto frame_address = data + static_cast<std::uint32_t>(frame) * 640U;
    for (std::int32_t tile_x = 0; tile_x < 4; ++tile_x) {
        for (std::int32_t tile_y = 0; tile_y < 5; ++tile_y) {
            const auto tile = frame_address
                + static_cast<std::uint32_t>(tile_x * 5 + tile_y) * 32U;
            for (std::int32_t row = 0; row < 8; ++row) {
                const std::array<std::uint8_t, 4> plane_pairs{
                    rom_->read8(tile + static_cast<std::uint32_t>(row * 2)),
                    rom_->read8(tile + static_cast<std::uint32_t>(row * 2 + 1)),
                    rom_->read8(tile + 16U + static_cast<std::uint32_t>(row * 2)),
                    rom_->read8(tile + 16U + static_cast<std::uint32_t>(row * 2 + 1)),
                };
                for (std::int32_t column = 0; column < 8; ++column) {
                    const auto mask = static_cast<std::uint8_t>(0x80U >> column);
                    std::uint8_t pixel{};
                    for (std::uint8_t plane = 0; plane < 4U; ++plane) {
                        if ((plane_pairs[plane] & mask) != 0U) {
                            pixel |= static_cast<std::uint8_t>(1U << plane);
                        }
                    }
                    target.set(x + tile_x * 8 + column, y + tile_y * 8 + row,
                        static_cast<std::uint8_t>(colour_index_base + pixel));
                }
            }
        }
    }
}

void ScaledTextRenderer::draw_ascii(
    std::string_view text,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour,
    std::uint8_t colour_index_base) const {
    starfox::app::perf::ScopedTimer
        perf_timer_text_ascii{
            starfox::app::perf::Bucket::text};

    const auto output_colour = static_cast<std::uint8_t>(
        colour_index_base + (colour & 0x0fU));
    for (const auto character : text) {
        const auto ascii = static_cast<std::uint8_t>(character);
        if (ascii == '\n') {
            y += 13;
            continue;
        }
        if (ascii < 32U) continue;
        const auto translated = rom_->read8(
            game_font_translation_ + static_cast<std::uint32_t>(ascii - 32U));
        const auto width = ascii == 32U ? std::uint8_t{5U}
            : rom_->read8(game_font_widths_ + translated);
        if (ascii != 32U && width != 0U) {
            const auto glyph = game_font_glyphs_
                + static_cast<std::uint32_t>(translated) * 24U;
            for (std::int32_t row = 0; row < 12; ++row) {
                const auto bits = rom_->read16(
                    glyph + static_cast<std::uint32_t>(row * 2));
                for (std::int32_t column = 0; column < width; ++column) {
                    if ((bits & (0x8000U >> column)) != 0U) {
                        target.set(x + column, y + row, output_colour);
                    }
                }
            }
        }
        x += width;
    }
}

std::int32_t ScaledTextRenderer::measure_ascii(std::string_view text) const {
    std::int32_t line_width{};
    std::int32_t maximum_width{};
    for (const auto character : text) {
        const auto ascii = static_cast<std::uint8_t>(character);
        if (ascii == '\n') {
            maximum_width = std::max(maximum_width, line_width);
            line_width = 0;
            continue;
        }
        if (ascii < 32U) continue;
        const auto translated = rom_->read8(
            game_font_translation_ + static_cast<std::uint32_t>(ascii - 32U));
        line_width += ascii == 32U ? 5
            : static_cast<std::int32_t>(
                rom_->read8(game_font_widths_ + translated));
    }
    return std::max(maximum_width, line_width);
}


namespace {

enum class HostAccent {
    none,
    acute,
    grave,
    circumflex,
    tilde,
    cedilla,
};

struct HostGlyph {
    std::uint8_t ascii{};
    HostAccent accent{HostAccent::none};
};

struct DecodedHostCodepoint {
    std::uint32_t value{};
    std::size_t bytes{1U};
};

DecodedHostCodepoint decode_host_utf8(
    std::string_view text,
    std::size_t offset) noexcept {

    const auto first = static_cast<std::uint8_t>(
        text[offset]);

    if (first < 0x80U) {
        return {first, 1U};
    }

    if ((first & 0xe0U) == 0xc0U
        && offset + 1U < text.size()) {

        const auto second = static_cast<std::uint8_t>(
            text[offset + 1U]);

        if ((second & 0xc0U) == 0x80U) {
            return {
                static_cast<std::uint32_t>(
                    ((first & 0x1fU) << 6U)
                    | (second & 0x3fU)),
                2U,
            };
        }
    }

    if ((first & 0xf0U) == 0xe0U
        && offset + 2U < text.size()) {

        const auto second = static_cast<std::uint8_t>(
            text[offset + 1U]);

        const auto third = static_cast<std::uint8_t>(
            text[offset + 2U]);

        if ((second & 0xc0U) == 0x80U
            && (third & 0xc0U) == 0x80U) {

            return {
                static_cast<std::uint32_t>(
                    ((first & 0x0fU) << 12U)
                    | ((second & 0x3fU) << 6U)
                    | (third & 0x3fU)),
                3U,
            };
        }
    }

    return {
        static_cast<std::uint32_t>('?'),
        1U,
    };
}

HostGlyph host_glyph(std::uint32_t codepoint) noexcept {

    if (codepoint <= 0x7fU) {
        return {
            static_cast<std::uint8_t>(codepoint),
            HostAccent::none,
        };
    }

    switch (codepoint) {
    // A / a
    case 0x00c0U:
        return {'A', HostAccent::grave};
    case 0x00c1U:
        return {'A', HostAccent::acute};
    case 0x00c2U:
        return {'A', HostAccent::circumflex};
    case 0x00c3U:
        return {'A', HostAccent::tilde};

    case 0x00e0U:
        return {'a', HostAccent::grave};
    case 0x00e1U:
        return {'a', HostAccent::acute};
    case 0x00e2U:
        return {'a', HostAccent::circumflex};
    case 0x00e3U:
        return {'a', HostAccent::tilde};

    // C / c
    case 0x00c7U:
        return {'C', HostAccent::cedilla};
    case 0x00e7U:
        return {'c', HostAccent::cedilla};

    // E / e
    case 0x00c9U:
        return {'E', HostAccent::acute};
    case 0x00caU:
        return {'E', HostAccent::circumflex};

    case 0x00e9U:
        return {'e', HostAccent::acute};
    case 0x00eaU:
        return {'e', HostAccent::circumflex};

    // I / i
    case 0x00cdU:
        return {'I', HostAccent::acute};
    case 0x00edU:
        return {'i', HostAccent::acute};

    // O / o
    case 0x00d3U:
        return {'O', HostAccent::acute};
    case 0x00d4U:
        return {'O', HostAccent::circumflex};
    case 0x00d5U:
        return {'O', HostAccent::tilde};

    case 0x00f3U:
        return {'o', HostAccent::acute};
    case 0x00f4U:
        return {'o', HostAccent::circumflex};
    case 0x00f5U:
        return {'o', HostAccent::tilde};

    // U / u
    case 0x00daU:
        return {'U', HostAccent::acute};
    case 0x00faU:
        return {'u', HostAccent::acute};

    default:
        return {'?', HostAccent::none};
    }
}

} // namespace

void ScaledTextRenderer::draw_utf8(
    std::string_view text,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour,
    std::uint8_t colour_index_base) const {
    starfox::app::perf::ScopedTimer
        perf_timer_text_utf8{
            starfox::app::perf::Bucket::text};


    const auto output_colour = static_cast<std::uint8_t>(
        colour_index_base + (colour & 0x0fU));

    const auto glyph_width =
        [this](std::uint8_t ascii) -> std::uint8_t {

        if (ascii == 32U) {
            return 5U;
        }

        if (ascii < 32U) {
            return 0U;
        }

        const auto translated = rom_->read8(
            game_font_translation_
            + static_cast<std::uint32_t>(
                ascii - 32U));

        return rom_->read8(
            game_font_widths_ + translated);
    };

    const auto draw_base =
        [this, &target, output_colour, &glyph_width](
            std::uint8_t ascii,
            std::int32_t draw_x,
            std::int32_t draw_y) {

        const auto width = glyph_width(ascii);

        if (ascii <= 32U || width == 0U) {
            return;
        }

        const auto translated = rom_->read8(
            game_font_translation_
            + static_cast<std::uint32_t>(
                ascii - 32U));

        const auto glyph =
            game_font_glyphs_
            + static_cast<std::uint32_t>(
                translated) * 24U;

        for (std::int32_t row = 0;
             row < 12;
             ++row) {

            const auto bits = rom_->read16(
                glyph
                + static_cast<std::uint32_t>(
                    row * 2));

            for (std::int32_t column = 0;
                 column < width;
                 ++column) {

                if ((bits
                    & (0x8000U >> column)) != 0U) {

                    target.set(
                        draw_x + column,
                        draw_y + row,
                        output_colour);
                }
            }
        }
    };

    const auto draw_accent =
        [&target, output_colour](
            HostAccent accent,
            std::int32_t draw_x,
            std::int32_t draw_y,
            std::uint8_t width) {

        if (accent == HostAccent::none
            || width == 0U) {
            return;
        }

        const auto middle =
            std::max<std::int32_t>(
                1,
                static_cast<std::int32_t>(
                    width) / 2);

        const auto pixel =
            [&target, output_colour](
                std::int32_t px,
                std::int32_t py) {

            target.set(
                px,
                py,
                output_colour);
        };

        switch (accent) {
        case HostAccent::acute:
            pixel(
                draw_x + middle,
                draw_y - 2);

            pixel(
                draw_x + middle + 1,
                draw_y - 3);

            break;

        case HostAccent::grave:
            pixel(
                draw_x + middle,
                draw_y - 2);

            pixel(
                draw_x + middle - 1,
                draw_y - 3);

            break;

        case HostAccent::circumflex:
            pixel(
                draw_x + middle - 1,
                draw_y - 2);

            pixel(
                draw_x + middle,
                draw_y - 3);

            pixel(
                draw_x + middle + 1,
                draw_y - 2);

            break;

        case HostAccent::tilde:
            pixel(
                draw_x + middle - 2,
                draw_y - 2);

            pixel(
                draw_x + middle - 1,
                draw_y - 3);

            pixel(
                draw_x + middle,
                draw_y - 3);

            pixel(
                draw_x + middle + 1,
                draw_y - 2);

            break;

        case HostAccent::cedilla:
            pixel(
                draw_x + middle,
                draw_y + 12);

            pixel(
                draw_x + middle - 1,
                draw_y + 13);

            break;

        case HostAccent::none:
        default:
            break;
        }
    };

    const auto start_x = x;

    std::size_t offset{};

    while (offset < text.size()) {

        const auto decoded =
            decode_host_utf8(
                text,
                offset);

        offset += decoded.bytes;

        if (decoded.value == '\n') {
            x = start_x;
            y += 15;
            continue;
        }

        if (decoded.value == '\r') {
            continue;
        }

        const auto glyph =
            host_glyph(decoded.value);

        const auto width =
            glyph_width(glyph.ascii);

        draw_base(
            glyph.ascii,
            x,
            y);

        draw_accent(
            glyph.accent,
            x,
            y,
            width);

        x += width;
    }
}

std::int32_t ScaledTextRenderer::measure_utf8(
    std::string_view text) const {

    const auto glyph_width =
        [this](std::uint8_t ascii)
            -> std::uint8_t {

        if (ascii == 32U) {
            return 5U;
        }

        if (ascii < 32U) {
            return 0U;
        }

        const auto translated = rom_->read8(
            game_font_translation_
            + static_cast<std::uint32_t>(
                ascii - 32U));

        return rom_->read8(
            game_font_widths_ + translated);
    };

    std::int32_t current{};
    std::int32_t maximum{};

    std::size_t offset{};

    while (offset < text.size()) {

        const auto decoded =
            decode_host_utf8(
                text,
                offset);

        offset += decoded.bytes;

        if (decoded.value == '\n') {
            maximum =
                std::max(
                    maximum,
                    current);

            current = 0;

            continue;
        }

        if (decoded.value == '\r') {
            continue;
        }

        const auto glyph =
            host_glyph(decoded.value);

        current +=
            static_cast<std::int32_t>(
                glyph_width(glyph.ascii));
    }

    return std::max(
        maximum,
        current);
}


void ScaledTextRenderer::draw_utf8_wrapped(
    std::string_view text,
    std::int32_t x,
    std::int32_t y,
    Framebuffer& target,
    std::uint8_t colour,
    std::uint8_t colour_index_base,
    std::int32_t right_clip,
    std::size_t max_lines) const {
    starfox::app::perf::ScopedTimer
        perf_timer_text_wrapped{
            starfox::app::perf::Bucket::text};


    if (text.empty()
        || max_lines == 0U) {
        return;
    }

    const auto origin_x = x;

    std::string line;
    std::size_t lines{};

    const auto flush =
        [&]() -> bool {

        if (line.empty()) {
            return lines < max_lines;
        }

        if (lines >= max_lines) {
            return false;
        }

        draw_utf8(
            line,
            origin_x,
            y,
            target,
            colour,
            colour_index_base);

        line.clear();

        ++lines;
        y += 13;

        return lines < max_lines;
    };

    std::size_t offset{};

    while (offset < text.size()) {
        if (text[offset] == '\r') {
            ++offset;
            continue;
        }

        if (text[offset] == '\n') {
            if (!flush()) {
                return;
            }

            ++offset;
            continue;
        }

        while (offset < text.size()
            && text[offset] == ' ') {
            ++offset;
        }

        if (offset >= text.size()) {
            break;
        }

        if (text[offset] == '\n') {
            continue;
        }

        const auto begin = offset;

        while (offset < text.size()
            && text[offset] != ' '
            && text[offset] != '\n'
            && text[offset] != '\r') {

            ++offset;
        }

        const auto word =
            text.substr(
                begin,
                offset - begin);

        auto candidate =
            line.empty()
            ? std::string{word}
            : line + " "
                + std::string{word};

        if (!line.empty()
            && origin_x
                + measure_utf8(candidate)
                    > right_clip) {

            if (!flush()) {
                return;
            }

            line.assign(
                word.data(),
                word.size());

        } else {
            line =
                std::move(candidate);
        }
    }

    if (!line.empty()
        && lines < max_lines) {

        draw_utf8(
            line,
            origin_x,
            y,
            target,
            colour,
            colour_index_base);
    }
}

} // namespace starfox::render
