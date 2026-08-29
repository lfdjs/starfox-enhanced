#include "starfox/localization/dialogue_catalog.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string_view>

namespace {

void require(
    bool condition,
    std::string_view message) {

    if (!condition) {
        std::cerr
            << "dialogue catalog test failed: "
            << message
            << '\n';

        std::exit(1);
    }
}

} // namespace

int main() {
    namespace fs = std::filesystem;

    const auto path =
        fs::temp_directory_path()
        / "starfox-enhanced-dialogue-test.tsv";

    {
        std::ofstream output{
            path,
            std::ios::trunc
        };

        output
            << "# teste\n"
            << "0x123456\tOlá, piloto!\n"
            << "0xabcdef\tLinha um\\nLinha dois\n";
    }

    starfox::localization::DialogueCatalog catalog;

    require(
        catalog.load(path),
        "catalog could not be loaded");

    require(
        catalog.size() == 2U,
        "catalog entry count is wrong");

    const auto first =
        catalog.find(0x123456U);

    require(
        first
            && *first == "Olá, piloto!",
        "UTF-8 translation was not preserved");

    const auto second =
        catalog.find(0xabcdefU);

    require(
        second
            && *second
                == "Linha um\nLinha dois",
        "escaped newline was not decoded");

    require(
        !catalog.find(0x111111U),
        "missing address unexpectedly resolved");

    std::error_code error;

    fs::remove(
        path,
        error);

    require(
        !error,
        "temporary catalog could not be removed");

    std::cout
        << "dialogue catalog tests passed\n";

    return 0;
}
