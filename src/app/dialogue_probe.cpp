#include "starfox/assets/rom.hpp"

#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

constexpr std::size_t maximum_dialogue_bytes = 192U;

std::uint32_t parse_address(
    std::string_view text) {

    if (text.empty()) {
        throw std::invalid_argument{
            "empty dialogue address"};
    }

    std::size_t parsed{};

    const auto value =
        std::stoull(
            std::string{text},
            &parsed,
            0);

    if (parsed != text.size()
        || value > 0xffffffULL) {

        throw std::invalid_argument{
            "dialogue address must be a 24-bit SNES address"};
    }

    const auto address =
        static_cast<std::uint32_t>(value);

    if ((address & 0xffffU) < 0x8000U) {
        throw std::invalid_argument{
            "dialogue address is outside the LoROM ROM window"};
    }

    return address;
}

std::string hexadecimal(
    std::uint32_t value,
    std::size_t digits) {

    std::ostringstream output;

    output
        << std::uppercase
        << std::hex
        << std::setw(
            static_cast<int>(digits))
        << std::setfill('0')
        << value;

    return output.str();
}

std::string printable_dialogue(
    const starfox::assets::RomImage& rom,
    std::uint32_t address,
    bool& terminated,
    bool& truncated) {

    std::string output;

    output.reserve(
        maximum_dialogue_bytes);

    terminated = false;
    truncated = false;

    for (std::size_t offset = 1U;
         offset <= maximum_dialogue_bytes;
         ++offset) {

        const auto byte =
            rom.read8(
                address
                + static_cast<std::uint32_t>(
                    offset));

        if (byte == 0U) {
            terminated = true;
            break;
        }

        if (byte == '\r'
            || byte == '\n') {

            output += "\\n";
            continue;
        }

        if (byte == '\t') {
            output += "\\t";
            continue;
        }

        if (byte == '\\') {
            output += "\\\\";
            continue;
        }

        if (byte >= 32U
            && byte <= 126U) {

            output.push_back(
                static_cast<char>(byte));

            continue;
        }

        output += "\\x";
        output += hexadecimal(
            byte,
            2U);
    }

    if (!terminated) {
        truncated = true;
    }

    return output;
}

void usage(
    const char* program) {

    std::cerr
        << "Uso:\n"
        << "  "
        << program
        << " <SF.SFC> <endereco>\n\n"
        << "Exemplo:\n"
        << "  "
        << program
        << " upstream-ultrastarfox/SF.SFC"
        << " 0x2D8000\n";
}

} // namespace

int main(
    int argc,
    char** argv) {

    if (argc != 3) {
        usage(argv[0]);
        return 2;
    }

    try {
        const auto rom =
            starfox::assets::RomImage::load(
                argv[1]);

        const auto address =
            parse_address(
                argv[2]);

        const auto colour =
            rom.read8(address);

        bool terminated{};
        bool truncated{};

        const auto dialogue =
            printable_dialogue(
                rom,
                address,
                terminated,
                truncated);

        std::cout
            << "STAR FOX DIALOGUE PROBE\n"
            << '\n'
            << "ADDRESS  0x"
            << hexadecimal(address, 6U)
            << '\n'
            << "COLOUR   0x"
            << hexadecimal(colour, 2U)
            << '\n'
            << "LENGTH   "
            << dialogue.size()
            << '\n'
            << "STATUS   "
            << (terminated
                    ? "TERMINATED"
                    : "LIMIT REACHED")
            << '\n'
            << '\n'
            << "TEXT\n"
            << "------------------------------------------------------------\n"
            << dialogue
            << '\n';

        if (truncated) {
            std::cout
                << '\n'
                << "AVISO: visualização limitada a "
                << maximum_dialogue_bytes
                << " bytes.\n";
        }

        return 0;

    } catch (const std::exception& error) {
        std::cerr
            << "starfox_dialogue_probe: "
            << error.what()
            << '\n';

        return 1;
    }
}
