#pragma once

#include "../../shared/include/engine.hpp"
#include "../../shared/include/v2.hpp"

#include <csignal>
#include <SDL2/SDL_pixels.h>
#include <SDL2/SDL_rect.h>
#include <SDL2/SDL_render.h>
#include <vector>

class World {
  public:
    World() = default;
    World(Settings, SDL_Renderer *);
    ~World();

    v2u   size;
    float render_scale;

    std::vector<std::vector<rgb>> map_data;

    SDL_Renderer *renderer;
    SDL_Texture  *tex;
    SDL_Rect      rect;

    void draw(v2f scroll);
    void update_map(nlohmann::json new_map_data);
};
