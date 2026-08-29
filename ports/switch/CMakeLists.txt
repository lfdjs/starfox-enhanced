if(NOT SWITCH AND NOT CMAKE_SYSTEM_NAME STREQUAL "NintendoSwitch")
    message(FATAL_ERROR
        "STARFOX_BUILD_SWITCH requires the devkitPro Switch toolchain. "
        "Configure with $DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake.")
endif()

if(NOT TARGET SDL3::SDL3)
    find_package(SDL3 CONFIG REQUIRED)
endif()

add_executable(starfox_switch
    ${PROJECT_SOURCE_DIR}/src/app/starfox_pc.cpp
    ${PROJECT_SOURCE_DIR}/src/app/runtime_input.cpp)
target_compile_definitions(starfox_switch PRIVATE
    STARFOX_SWITCH_RUNTIME=1
    __SWITCH__=1)
target_link_libraries(starfox_switch PRIVATE starfox_core SDL3::SDL3)

set(STARFOX_SWITCH_TITLE "Star Fox Enhanced" CACHE STRING
    "Nintendo Switch application title")
set(STARFOX_SWITCH_AUTHOR "Star Fox Enhanced contributors" CACHE STRING
    "Nintendo Switch application author")

find_program(STARFOX_NACPTOOL nacptool REQUIRED)
find_program(STARFOX_ELF2NRO elf2nro REQUIRED)

set(switch_nacp "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch.nacp")
set(switch_nro "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch.nro")
add_custom_command(OUTPUT "${switch_nacp}"
    COMMAND "${STARFOX_NACPTOOL}" --create
        "${STARFOX_SWITCH_TITLE}" "${STARFOX_SWITCH_AUTHOR}"
        "${PROJECT_VERSION}" "${switch_nacp}"
    DEPENDS starfox_switch
    VERBATIM)
add_custom_command(OUTPUT "${switch_nro}"
    COMMAND "${STARFOX_ELF2NRO}" "$<TARGET_FILE:starfox_switch>"
        "${switch_nro}" --nacp "${switch_nacp}"
    DEPENDS starfox_switch "${switch_nacp}"
    VERBATIM)
add_custom_target(starfox_switch_nro ALL DEPENDS "${switch_nro}")

install(FILES "${switch_nro}" DESTINATION switch/starfox-enhanced)
install(DIRECTORY "${PROJECT_SOURCE_DIR}/localization/"
    DESTINATION switch/starfox-enhanced/localization)
