#pragma once

#include "../../shared/include/v2.hpp"
#include "../include/client.hpp"
#include "../include/world.hpp"

#include <mutex>
#include <SDL2/SDL_rect.h>
#include <SDL2/SDL_render.h>
#include <string>
#include <thread>

struct Game {
    SDL_Window   *window;
    SDL_Renderer *renderer;
    float         target_framerate;
    float         dt;
    bool          running;
    bool          moving;
    v2f           scroll;

    World    world;
    Client   client;
    Settings settings;

    std::thread world_fetch_thread;
    std::mutex  message_handle_mutex;

    Game(Settings);
    ~Game(void);

    void fetch_world(void);
    void update(void);
};

int exit_failure(std::string message);
