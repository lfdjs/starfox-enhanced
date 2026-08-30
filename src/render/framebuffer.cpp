#include "starfox/render/framebuffer.hpp"
#include "starfox/app/perf_profiler.hpp"
#include "starfox/render/palette.hpp"

#include <array>
#include <fstream>
#include <stdexcept>

namespace starfox::render {
namespace {

std::int32_t mosaic_coordinate(
    std::int32_t coordinate, std::int32_t size) noexcept {
    auto remainder = coordinate % size;
    if (remainder < 0) remainder += size;
    return coordinate - remainder;
}

void write_u16(std::ofstream& output, std::uint16_t value) {
    output.put(static_cast<char>(value & 0xffU));
    output.put(static_cast<char>((value >> 8U) & 0xffU));
}

void write_u32(std::ofstream& output, std::uint32_t value) {
    write_u16(output, static_cast<std::uint16_t>(value & 0xffffU));
    write_u16(output, static_cast<std::uint16_t>((value >> 16U) & 0xffffU));
}

} // namespace

void composite_transparent_layer(
    const Framebuffer& source,
    Framebuffer& destination,
    const LayerCompositeSettings& settings) noexcept {

    starfox::app::perf::ScopedTimer
        perf_timer_composite{
            starfox::app::perf::Bucket::composite};

    const auto source_width =
        static_cast<std::int32_t>(
            source.width());

    const auto source_height =
        static_cast<std::int32_t>(
            source.height());

    const auto destination_width =
        static_cast<std::int32_t>(
            destination.width());

    const auto destination_height =
        static_cast<std::int32_t>(
            destination.height());

    const auto mosaic_enabled =
        settings.mosaic_layer_mask != 0U
        && (settings.mosaic
            & settings.mosaic_layer_mask)
            != 0U;

    // ========================================================
    // COMMON FAST PATH
    //
    // Most gameplay layers have mosaic disabled.
    //
    // The old implementation scanned the complete source and,
    // for every pixel:
    //
    //   - recalculated destination_x/y
    //   - checked four clip comparisons
    //   - called source.get()
    //   - called destination.set()
    //
    // Clip the rectangle once, acquire row pointers once per
    // scanline, and copy only non-transparent source pixels.
    // ========================================================

    if (!mosaic_enabled) {

        const auto destination_left =
            std::max({
                0,
                settings.clip_left,
                settings.offset_x});

        const auto destination_top =
            std::max({
                0,
                settings.clip_top,
                settings.offset_y});

        const auto destination_right =
            std::min({
                destination_width,
                settings.clip_right,
                settings.offset_x
                    + source_width});

        const auto destination_bottom =
            std::min({
                destination_height,
                settings.clip_bottom,
                settings.offset_y
                    + source_height});

        if (destination_left
                >= destination_right
            || destination_top
                >= destination_bottom) {

            return;
        }

        const auto source_left =
            destination_left
            - settings.offset_x;

        const auto copy_width =
            destination_right
            - destination_left;

        for (auto destination_y =
                 destination_top;
             destination_y
                 < destination_bottom;
             ++destination_y) {

            const auto source_y =
                destination_y
                - settings.offset_y;

            const auto* source_row =
                source.row_data(
                    static_cast<
                        std::uint32_t>(
                            source_y));

            auto* destination_row =
                destination.row_data(
                    static_cast<
                        std::uint32_t>(
                            destination_y));

            const auto* src =
                source_row
                + source_left;

            auto* dst =
                destination_row
                + destination_left;

            for (auto column = 0;
                 column < copy_width;
                 ++column) {

                const auto colour =
                    src[column];

                if (colour != 0U) {
                    dst[column] =
                        colour;
                }
            }
        }

        return;
    }

    // ========================================================
    // MOSAIC PATH
    //
    // Mosaic requires sampling a different source coordinate,
    // but clipping and destination row access can still be
    // moved outside the inner pixel work.
    // ========================================================

    const auto mosaic_size =
        static_cast<std::int32_t>(
            (settings.mosaic >> 4U)
            + 1U);

    const auto destination_left =
        std::max(
            0,
            settings.clip_left);

    const auto destination_top =
        std::max(
            0,
            settings.clip_top);

    const auto destination_right =
        std::min(
            destination_width,
            settings.clip_right);

    const auto destination_bottom =
        std::min(
            destination_height,
            settings.clip_bottom);

    if (destination_left
            >= destination_right
        || destination_top
            >= destination_bottom) {

        return;
    }

    for (auto destination_y =
             destination_top;
         destination_y
             < destination_bottom;
         ++destination_y) {

        const auto logical_y =
            destination_y
            - settings.mosaic_origin_y;

        const auto sampled_logical_y =
            mosaic_coordinate(
                logical_y,
                mosaic_size);

        const auto source_y =
            sampled_logical_y
            + settings.mosaic_origin_y
            - settings.offset_y;

        if (source_y < 0
            || source_y >= source_height) {

            continue;
        }

        const auto* source_row =
            source.row_data(
                static_cast<
                    std::uint32_t>(
                        source_y));

        auto* destination_row =
            destination.row_data(
                static_cast<
                    std::uint32_t>(
                        destination_y));

        for (auto destination_x =
                 destination_left;
             destination_x
                 < destination_right;
             ++destination_x) {

            const auto logical_x =
                destination_x
                - settings.mosaic_origin_x;

            const auto sampled_logical_x =
                mosaic_coordinate(
                    logical_x,
                    mosaic_size);

            const auto source_x =
                sampled_logical_x
                + settings.mosaic_origin_x
                - settings.offset_x;

            if (source_x < 0
                || source_x >= source_width) {

                continue;
            }

            const auto colour =
                source_row[source_x];

            if (colour != 0U) {

                destination_row[
                    destination_x] =
                    colour;
            }
        }
    }
}

void write_bmp(const Framebuffer& framebuffer, const std::filesystem::path& path) {
    write_bmp(framebuffer, path, preview_palette());
}

void write_bmp(
    const Framebuffer& framebuffer,
    const std::filesystem::path& path,
    std::span<const Rgba8> palette) {
    if (palette.empty()) {
        throw std::invalid_argument{"bitmap palette is empty"};
    }
    if (!path.parent_path().empty()) {
        std::filesystem::create_directories(path.parent_path());
    }
    std::ofstream output{path, std::ios::binary};
    if (!output) {
        throw std::runtime_error{"unable to create bitmap: " + path.string()};
    }

    const auto row_bytes = ((framebuffer.width() * 3U) + 3U) & ~3U;
    const auto pixel_bytes = row_bytes * framebuffer.height();
    output.write("BM", 2);
    write_u32(output, 54U + pixel_bytes);
    write_u16(output, 0);
    write_u16(output, 0);
    write_u32(output, 54);
    write_u32(output, 40);
    write_u32(output, framebuffer.width());
    write_u32(output, framebuffer.height());
    write_u16(output, 1);
    write_u16(output, 24);
    write_u32(output, 0);
    write_u32(output, pixel_bytes);
    write_u32(output, 2'835);
    write_u32(output, 2'835);
    write_u32(output, 0);
    write_u32(output, 0);

    const std::array<char, 3> padding{};
    for (std::uint32_t y = framebuffer.height(); y-- > 0;) {
        for (std::uint32_t x = 0; x < framebuffer.width(); ++x) {
            const auto pixel = framebuffer.get(x, y);
            const auto colour = palette[std::min<std::size_t>(
                pixel, palette.size() - 1U)];
            output.put(static_cast<char>(colour.b));
            output.put(static_cast<char>(colour.g));
            output.put(static_cast<char>(colour.r));
        }
        output.write(padding.data(), static_cast<std::streamsize>(row_bytes - framebuffer.width() * 3U));
    }
}

} // namespace starfox::render
