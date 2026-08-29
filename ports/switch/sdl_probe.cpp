#include <SDL3/SDL.h>

#include <switch.h>

#include <cstdio>
#include <cstring>

namespace {

void debug_message(const char* message) {
    if (message == nullptr) {
        return;
    }

    svcOutputDebugString(
        message,
        std::strlen(message));
}

void debug_sdl_error(const char* stage) {
    char buffer[768]{};

    std::snprintf(
        buffer,
        sizeof(buffer),
        "[SFE SDL PROBE] %s FAILED: %s\n",
        stage,
        SDL_GetError());

    debug_message(buffer);
}

void debug_renderer_drivers() {
    const int count =
        SDL_GetNumRenderDrivers();

    char buffer[256]{};

    std::snprintf(
        buffer,
        sizeof(buffer),
        "[SFE SDL PROBE] renderer drivers: %d\n",
        count);

    debug_message(buffer);

    for (int index = 0;
         index < count;
         ++index) {

        const char* name =
            SDL_GetRenderDriver(index);

        std::snprintf(
            buffer,
            sizeof(buffer),
            "[SFE SDL PROBE] renderer[%d]=%s\n",
            index,
            name != nullptr ? name : "(null)");

        debug_message(buffer);
    }
}

} // namespace

int main() {
    debug_message(
        "[SFE SDL PROBE] main entered\n");

    SDL_SetHint(
        SDL_HINT_RENDER_DRIVER,
        "opengles2");

    debug_message(
        "[SFE SDL PROBE] before SDL_Init(VIDEO)\n");

    if (!SDL_Init(SDL_INIT_VIDEO)) {
        debug_sdl_error("SDL_Init");
        return 10;
    }

    debug_message(
        "[SFE SDL PROBE] SDL_Init(VIDEO) OK\n");

    debug_renderer_drivers();

    debug_message(
        "[SFE SDL PROBE] before SDL_CreateWindow\n");

    SDL_Window* window =
        SDL_CreateWindow(
            "Star Fox Enhanced SDL Probe",
            1280,
            720,
            SDL_WINDOW_FULLSCREEN
                | SDL_WINDOW_OPENGL);

    if (window == nullptr) {
        debug_sdl_error(
            "SDL_CreateWindow");

        SDL_Quit();

        return 20;
    }

    debug_message(
        "[SFE SDL PROBE] SDL_CreateWindow OK\n");

    // Useful checkpoint: if Ryubing crashes after this message,
    // the failure occurs while creating the GLES2/EGL renderer.
    debug_message(
        "[SFE SDL PROBE] before SDL_CreateRenderer(opengles2)\n");

    SDL_Renderer* renderer =
        SDL_CreateRenderer(
            window,
            "opengles2");

    if (renderer == nullptr) {
        debug_sdl_error(
            "SDL_CreateRenderer(opengles2)");

        SDL_DestroyWindow(window);
        SDL_Quit();

        return 30;
    }

    debug_message(
        "[SFE SDL PROBE] SDL_CreateRenderer(opengles2) OK\n");

    if (!SDL_SetRenderDrawColor(
            renderer,
            16,
            32,
            64,
            255)) {

        debug_sdl_error(
            "SDL_SetRenderDrawColor");
    }

    debug_message(
        "[SFE SDL PROBE] before first present\n");

    bool running = true;

    for (int frame = 0;
         frame < 300 && running;
         ++frame) {

        SDL_Event event{};

        while (SDL_PollEvent(&event)) {
            if (event.type
                == SDL_EVENT_QUIT) {

                running = false;
            }
        }

        if (!SDL_RenderClear(renderer)) {
            debug_sdl_error(
                "SDL_RenderClear");

            break;
        }

        if (!SDL_RenderPresent(renderer)) {
            debug_sdl_error(
                "SDL_RenderPresent");

            break;
        }

        if (frame == 0) {
            debug_message(
                "[SFE SDL PROBE] first present OK\n");
        }

        if (frame == 60) {
            debug_message(
                "[SFE SDL PROBE] 60 frames OK\n");
        }

        if (frame == 180) {
            debug_message(
                "[SFE SDL PROBE] 180 frames OK\n");
        }

        SDL_Delay(16);
    }

    debug_message(
        "[SFE SDL PROBE] shutting down normally\n");

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);

    SDL_Quit();

    return 0;
}
