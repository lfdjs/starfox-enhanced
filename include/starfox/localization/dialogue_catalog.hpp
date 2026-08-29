#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

namespace starfox::localization {

class DialogueCatalog {
public:
    [[nodiscard]] bool load(
        const std::filesystem::path& path) noexcept;

    void clear() noexcept {
        entries_.clear();
    }

    [[nodiscard]] std::optional<std::string_view> find(
        std::uint32_t address) const noexcept;

    [[nodiscard]] std::size_t size() const noexcept {
        return entries_.size();
    }

    [[nodiscard]] bool empty() const noexcept {
        return entries_.empty();
    }

private:
    std::unordered_map<std::uint32_t, std::string> entries_;
};

} // namespace starfox::localization
