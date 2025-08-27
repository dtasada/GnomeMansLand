#include "../../shared/include/engine.hpp"
#include "../include/game.hpp"
#include "../include/sprite.hpp"

#include <toml++/toml.hpp>

int main(int argc, char *argv[]) {
    srand(time(nullptr));

    Game game(Settings::parse());

    // Sprite local_player(game.renderer, "./resources/grass.png", {0, 0, 100, 100});
    // Sprite remote_player(game.renderer, "./resources/grass.png", {0, 200, 200, 200});

    SDL_Event      event;
    const uint8_t *scancodes = SDL_GetKeyboardState(NULL);

    uint32_t last_server_poll = SDL_GetTicks();
    while (game.running) {
        SDL_PollEvent(&event);
        SDL_PumpEvents();

        switch (event.type) {
            case SDL_QUIT: game.running = false; break;
            case SDL_KEYDOWN:
                switch (event.key.keysym.sym) {
                    case SDLK_ESCAPE: game.running = false; break;
                    case SDLK_UP:     game.world.render_scale *= 2; break;
                    case SDLK_DOWN:   game.world.render_scale /= 2; break;
                    case SDLK_SPACE:  game.fetch_world(); break;
                }
                break;
            case SDL_MOUSEBUTTONDOWN: game.moving = true; break;
            case SDL_MOUSEBUTTONUP:   game.moving = false; break;
            case SDL_MOUSEMOTION:
                if (game.moving) {
                    game.scroll.x += event.motion.xrel;
                    game.scroll.y += event.motion.yrel;
                }
                break;
        }

        if (scancodes[SDL_SCANCODE_ESCAPE]) game.running = false;
        // if (scancodes[SDL_SCANCODE_W]) local_player.rect.y -= 1;
        // if (scancodes[SDL_SCANCODE_S]) local_player.rect.y += 1;
        // if (scancodes[SDL_SCANCODE_A]) local_player.rect.x -= 1;
        // if (scancodes[SDL_SCANCODE_D]) local_player.rect.x += 1;

        uint32_t now = SDL_GetTicks();
        if (now - last_server_poll > game.settings.multiplayer.server_polling_interval) {
            last_server_poll = now;
        }

        SDL_RenderClear(game.renderer);

        game.update();

        SDL_RenderPresent(game.renderer);

        SDL_Delay(1000.0f / game.target_framerate);
    }

    return EXIT_SUCCESS;
}
