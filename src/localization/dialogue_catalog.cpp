#include "starfox/localization/dialogue_catalog.hpp"

#include <fstream>
#include <limits>
#include <string>

namespace starfox::localization {
namespace {

std::string decode_escapes(std::string_view input) {
    std::string result;
    result.reserve(input.size());

    for (std::size_t index = 0U;
         index < input.size();
         ++index) {

        const auto character = input[index];

        if (character != '\\'
            || index + 1U >= input.size()) {

            result.push_back(character);
            continue;
        }

        const auto next = input[++index];

        switch (next) {
        case 'n':
            result.push_back('\n');
            break;

        case 't':
            result.push_back('\t');
            break;

        case '\\':
            result.push_back('\\');
            break;

        default:
            result.push_back('\\');
            result.push_back(next);
            break;
        }
    }

    return result;
}

} // namespace

bool DialogueCatalog::load(
    const std::filesystem::path& path) noexcept {

    try {
        std::ifstream input{path};

        if (!input) {
            return false;
        }

        std::unordered_map<std::uint32_t, std::string>
            loaded;

        std::string line;

        while (std::getline(input, line)) {
            if (!line.empty()
                && line.back() == '\r') {
                line.pop_back();
            }

            const auto first =
                line.find_first_not_of(" \t");

            if (first == std::string::npos
                || line[first] == '#') {
                continue;
            }

            const auto separator =
                line.find('\t', first);

            if (separator == std::string::npos) {
                return false;
            }

            const auto address_text =
                line.substr(
                    first,
                    separator - first);

            auto translation =
                line.substr(separator + 1U);

            if (translation.empty()) {
                return false;
            }

            std::size_t parsed{};

            const auto value =
                std::stoull(
                    address_text,
                    &parsed,
                    0);

            if (parsed != address_text.size()
                || value > 0xffffffULL) {
                return false;
            }

            loaded[
                static_cast<std::uint32_t>(value)] =
                    decode_escapes(translation);
        }

        entries_ = std::move(loaded);

        return true;

    } catch (...) {
        return false;
    }
}

std::optional<std::string_view>
DialogueCatalog::find(
    std::uint32_t address) const noexcept {

    const auto found =
        entries_.find(address);

    if (found == entries_.end()) {
        return std::nullopt;
    }

    return std::string_view{
        found->second
    };
}

} // namespace starfox::localization
