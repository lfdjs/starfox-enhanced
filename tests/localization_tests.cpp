#include "starfox/localization/language.hpp"

#include <cstdlib>
#include <iostream>
#include <string_view>

namespace {

void require(bool condition, std::string_view message) {
    if (!condition) {
        std::cerr
            << "localization test failed: "
            << message
            << '\n';

        std::exit(1);
    }
}

} // namespace

int main() {
    using starfox::localization::Language;
    using starfox::localization::TextId;
    using starfox::localization::language_name;
    using starfox::localization::text;

    require(
        text(Language::english, TextId::start_game)
            == "START GAME",
        "English START GAME changed");

    require(
        text(Language::portuguese_br, TextId::start_game)
            == "INICIAR JOGO",
        "PT-BR START GAME translation is wrong");

    require(
        text(Language::portuguese_br, TextId::pregame_setup)
            == "CONFIGURAÇÃO",
        "PT-BR CONFIGURACAO lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::options)
            == "OPÇÕES",
        "PT-BR OPCOES lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::experience)
            == "EXPERIÊNCIA",
        "PT-BR EXPERIENCIA lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::display_4_3)
            == "4 POR 3 PADRÃO",
        "PT-BR PADRAO lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::action)
            == "AÇÃO",
        "PT-BR ACAO lost UTF-8 accents");

    require(
        language_name(Language::portuguese_br)
            == "PORTUGUÊS BR",
        "PT-BR language label lost UTF-8 accents");

    require(
        text(Language::portuguese_br, TextId::color_green)
            == "VERDE",
        "PT-BR green translation is wrong");

    require(
        text(Language::portuguese_br, TextId::color_red)
            == "VERMELHO",
        "PT-BR red translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_score)
            == "PONTOS",
        "PT-BR HUD PONTOS translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_team)
            == "EQUIPE",
        "PT-BR HUD EQUIPE translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_pause)
            == "PAUSA",
        "PT-BR HUD PAUSA translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_enemy)
            == "INIMIGO",
        "PT-BR HUD INIMIGO translation is wrong");

    require(
        text(Language::portuguese_br, TextId::hud_shield)
            == "ESCUDO",
        "PT-BR HUD ESCUDO translation is wrong");

    require(
        text(Language::english, TextId::hud_shield)
            == "SHIELD",
        "English HUD SHIELD translation changed");

    std::cout << "localization UTF-8 tests passed\n";

    return 0;
}
