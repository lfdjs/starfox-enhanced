#include "starfox/localization/language.hpp"

namespace starfox::localization {

std::string_view text(
    Language language,
    TextId id) noexcept {

    const auto pt = language == Language::portuguese_br;

    switch (id) {
    case TextId::title:
        return "STAR FOX ENHANCED";

    case TextId::pregame_setup:
        return pt ? "CONFIGURAÇÃO" : "PRE-GAME SETUP";

    case TextId::options_title:
        return pt ? "OPÇÕES" : "OPTIONS";

    case TextId::experience:
        return pt ? "EXPERIÊNCIA" : "EXPERIENCE";

    case TextId::game_pace:
        return pt ? "RITMO DO JOGO" : "GAME PACE";

    case TextId::render_fps:
        return pt ? "FPS DE RENDERIZAÇÃO" : "RENDER FPS";

    case TextId::display:
        return pt ? "TELA" : "DISPLAY";

    case TextId::controller:
        return pt ? "CONTROLE" : "CONTROLLER";

    case TextId::options:
        return pt ? "OPÇÕES" : "OPTIONS";

    case TextId::start_game:
        return pt ? "INICIAR JOGO" : "START GAME";

    case TextId::god_mode:
        return pt ? "MODO DEUS" : "GOD MODE";

    case TextId::onscreen_fps:
        return pt ? "FPS NA TELA" : "ON-SCREEN FPS";

    case TextId::crosshair_color:
        return pt ? "COR DA MIRA" : "CROSSHAIR COLOR";

    case TextId::language:
        return pt ? "IDIOMA" : "LANGUAGE";

    case TextId::customize_screen:
        return pt ? "AJUSTAR TELA" : "CUSTOMIZE SCREEN";

    case TextId::back:
        return pt ? "VOLTAR" : "BACK";

    case TextId::on:
        return pt ? "LIGADO" : "ON";

    case TextId::off:
        return pt ? "DESLIGADO" : "OFF";

    case TextId::open:
        return pt ? "A  ABRIR" : "A  OPEN";

    case TextId::remap:
        return pt ? "A  MAPEAR" : "A  REMAP";

    case TextId::change_hint:
        return pt
            ? "A/ESQ/DIR  ALTERA"
            : "A/LEFT/RIGHT  CHANGE";

    case TextId::back_hint:
        return pt ? "B  VOLTAR" : "B  BACK";

    case TextId::choose_hint:
        return pt
            ? "D-PAD ESCOLHE  A CONFIRMA"
            : "D-PAD CHOOSE  A SELECT";

    case TextId::begin_hint:
        return pt ? "START  INICIA" : "START  BEGIN";

    case TextId::unlocked_20_hz:
        return pt ? "20 HZ LIVRE" : "UNLOCKED 20 HZ";

    case TextId::original_speed:
        return "ORIGINAL";

    case TextId::display_4_3:
        return pt ? "4 POR 3 PADRÃO" : "4 BY 3 STANDARD";

    case TextId::display_16_9:
        return pt ? "16 POR 9 AMPLO" : "16 BY 9 WIDE";

    case TextId::display_16_10:
        return pt ? "16 POR 10 AMPLO" : "16 BY 10 WIDE";

    case TextId::display_21_9:
        return pt ? "21 POR 9 ULTRA" : "21 BY 9 ULTRA";

    case TextId::display_32_9:
        return pt ? "32 POR 9 SUPER" : "32 BY 9 SUPER";

    case TextId::original_experience:
        return "ORIGINAL";

    case TextId::starfox_ex_experience:
        return "STARFOX EX";

    case TextId::color_green:
        return pt ? "VERDE" : "GREEN";

    case TextId::color_white:
        return pt ? "BRANCO" : "WHITE";

    case TextId::color_blue:
        return pt ? "AZUL" : "BLUE";

    case TextId::color_red:
        return pt ? "VERMELHO" : "RED";

    case TextId::color_yellow:
        return pt ? "AMARELO" : "YELLOW";

    case TextId::color_cyan:
        return pt ? "CIANO" : "CYAN";

    case TextId::color_magenta:
        return "MAGENTA";

    case TextId::color_orange:
        return pt ? "LARANJA" : "ORANGE";

    case TextId::hud_layout:
        return pt ? "LAYOUT DO HUD" : "HUD LAYOUT";

    case TextId::reset:
        return pt ? "RESETAR" : "RESET";

    case TextId::done:
        return pt ? "CONCLUIR" : "DONE";

    case TextId::controller_remap:
        return pt ? "MAPEAR CONTROLE" : "CONTROLLER REMAP";

    case TextId::dpad_choose:
        return pt ? "D-PAD  ESCOLHE" : "D-PAD  CHOOSE";

    case TextId::keyboard:
        return pt ? "TECLADO" : "KEYBOARD";

    case TextId::action:
        return pt ? "AÇÃO" : "ACTION";

    case TextId::press_key_control:
        return pt
            ? "PRESSIONE TECLA OU CONTROLE"
            : "PRESS A KEY OR CONTROL";

    case TextId::left_right_device:
        return pt
            ? "ESQ/DIR  DISPOSITIVO"
            : "LEFT/RIGHT  DEVICE";

    case TextId::bind_defaults:
        return pt
            ? "A  MAPEAR   Y  PADRÃO"
            : "A  BIND   Y  DEFAULTS";

    case TextId::remap_done:
        return pt
            ? "B/START/ESC  CONCLUIR"
            : "B/START/ESC  DONE";

    case TextId::hud_score:
        return pt ? "PONTOS" : "SCORE";

    case TextId::hud_total:
        return pt ? "TOTAL" : "TOTAL SCORE";

    case TextId::hud_team:
        return pt ? "EQUIPE" : "TEAM";

    case TextId::hud_down:
        return pt ? "FORA" : "DOWN";

    case TextId::hud_pause:
        return pt ? "PAUSA" : "PAUSE";

    case TextId::hud_enemy:
        return pt ? "INIMIGO" : "ENEMY";

    case TextId::hud_shield:
        return pt ? "ESCUDO" : "SHIELD";

    case TextId::count:
    default:
        return {};
    }
}

std::string_view language_name(Language language) noexcept {
    return language == Language::portuguese_br
        ? std::string_view{"PORTUGUÊS BR"}
        : std::string_view{"ENGLISH"};
}

} // namespace starfox::localization
