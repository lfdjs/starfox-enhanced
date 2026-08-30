if(NOT SWITCH AND NOT CMAKE_SYSTEM_NAME STREQUAL "NintendoSwitch")
    message(FATAL_ERROR
        "STARFOX_BUILD_SWITCH requires the devkitPro Switch toolchain. "
        "Configure with $DEVKITPRO/portlibs/switch/bin/aarch64-none-elf-cmake.")
endif()

if(NOT TARGET SDL3::SDL3)
    find_package(SDL3 CONFIG REQUIRED)
endif()

add_executable(starfox_switch
    ${PROJECT_SOURCE_DIR}/src/app/control_visual_profile.cpp
    ${PROJECT_SOURCE_DIR}/src/app/starfox_pc.cpp
    ${PROJECT_SOURCE_DIR}/src/app/runtime_input.cpp)
target_compile_definitions(starfox_switch PRIVATE
    STARFOX_SWITCH_RUNTIME=1
    __SWITCH__=1)
target_link_libraries(starfox_switch PRIVATE starfox_core SDL3::SDL3)

# Temporary Switch performance profiler. Keep the same profiler
# configuration in the core and application translation units so
# the shared inline counters form one process-wide data set.
target_compile_definitions(
    starfox_core
    PRIVATE
        STARFOX_PERF_PROFILER=1
        STARFOX_PERF_SWITCH=1)

target_compile_definitions(
    starfox_switch
    PRIVATE
        STARFOX_PERF_PROFILER=1
        STARFOX_PERF_SWITCH=1)

# The Switch runtime spends most of its time in the software SNES/Super FX
# presentation path. Enable whole-program optimisation for project-owned code
# in Release builds; prebuilt SDL/libnx libraries remain ordinary link inputs.
include(CheckIPOSupported)

check_ipo_supported(
    RESULT STARFOX_SWITCH_IPO_SUPPORTED
    OUTPUT STARFOX_SWITCH_IPO_ERROR
    LANGUAGES CXX)

if(STARFOX_SWITCH_IPO_SUPPORTED)
    set_property(
        TARGET starfox_core
        PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

    set_property(
        TARGET starfox_switch
        PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)

    message(STATUS
        "Star Fox Switch: interprocedural optimisation enabled")
else()
    message(STATUS
        "Star Fox Switch: IPO unavailable: ${STARFOX_SWITCH_IPO_ERROR}")
endif()

set(STARFOX_SWITCH_TITLE "Star Fox Enhanced" CACHE STRING
    "Nintendo Switch application title")
set(STARFOX_SWITCH_AUTHOR "Star Fox Enhanced contributors" CACHE STRING
    "Nintendo Switch application author")

find_program(STARFOX_NACPTOOL nacptool REQUIRED)
find_program(STARFOX_ELF2NRO elf2nro REQUIRED)

set(switch_nacp "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch.nacp")
set(switch_nro "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch.nro")
set(switch_romfs "${CMAKE_CURRENT_BINARY_DIR}/romfs")
file(REMOVE_RECURSE "${switch_romfs}")
file(MAKE_DIRECTORY "${switch_romfs}/control_hints")
# STARFOX_CONTROL_HINT_ROMFS_PASS05
set(switch_control_hint_sources)
foreach(control_hint_asset
    switch_pro_controller.qoi
    switch_single_joycon.qoi
    switch_dual_joycon.qoi
    switch_handheld.qoi)

    list(APPEND switch_control_hint_sources
        "${PROJECT_SOURCE_DIR}/assets/control_hints/${control_hint_asset}")
    configure_file(
        "${PROJECT_SOURCE_DIR}/assets/control_hints/${control_hint_asset}"
        "${switch_romfs}/control_hints/${control_hint_asset}"
        COPYONLY)

endforeach()
add_custom_command(OUTPUT "${switch_nacp}"
    COMMAND "${STARFOX_NACPTOOL}" --create
        "${STARFOX_SWITCH_TITLE}" "${STARFOX_SWITCH_AUTHOR}"
        "${PROJECT_VERSION}" "${switch_nacp}"
    DEPENDS starfox_switch
    VERBATIM)
add_custom_command(OUTPUT "${switch_nro}"
    COMMAND "${STARFOX_ELF2NRO}" "$<TARGET_FILE:starfox_switch>"
        "${switch_nro}" "--nacp=${switch_nacp}"
        "--romfsdir=${switch_romfs}"
    DEPENDS starfox_switch "${switch_nacp}" ${switch_control_hint_sources}
    VERBATIM)
add_custom_target(starfox_switch_nro ALL DEPENDS "${switch_nro}")

install(FILES "${switch_nro}" DESTINATION switch/starfox-enhanced)
install(DIRECTORY "${PROJECT_SOURCE_DIR}/localization/"
    DESTINATION switch/starfox-enhanced/localization)

# ------------------------------------------------------------
# SDL3 / EGL diagnostic NRO
# ------------------------------------------------------------

add_executable(
    starfox_switch_sdl_probe
    EXCLUDE_FROM_ALL
    ${CMAKE_CURRENT_SOURCE_DIR}/sdl_probe.cpp)

target_compile_definitions(
    starfox_switch_sdl_probe
    PRIVATE
        __SWITCH__=1)

target_link_libraries(
    starfox_switch_sdl_probe
    PRIVATE
        SDL3::SDL3)

set(
    switch_sdl_probe_nacp
    "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch_sdl_probe.nacp")

set(
    switch_sdl_probe_nro
    "${CMAKE_CURRENT_BINARY_DIR}/starfox_switch_sdl_probe.nro")

add_custom_command(
    OUTPUT
        "${switch_sdl_probe_nacp}"

    COMMAND
        "${STARFOX_NACPTOOL}"
        --create
        "Star Fox SDL Probe"
        "Star Fox Enhanced contributors"
        "${PROJECT_VERSION}"
        "${switch_sdl_probe_nacp}"

    VERBATIM)

add_custom_command(
    OUTPUT
        "${switch_sdl_probe_nro}"

    COMMAND
        "${STARFOX_ELF2NRO}"
        "$<TARGET_FILE:starfox_switch_sdl_probe>"
        "${switch_sdl_probe_nro}"
        "--nacp=${switch_sdl_probe_nacp}"

    DEPENDS
        starfox_switch_sdl_probe
        "${switch_sdl_probe_nacp}"

    VERBATIM)

add_custom_target(
    starfox_switch_sdl_probe_nro
    DEPENDS
        "${switch_sdl_probe_nro}")
