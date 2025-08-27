#include "../../shared/include/engine.hpp"
#include "../include/world.hpp"

#include <cstring>
#include <omp.h>
#include <SDL2/SDL_pixels.h>
#include <SDL2/SDL_render.h>
#include <SDL2/SDL_surface.h>
#include <string>

World::World(Settings st, SDL_Renderer *renderer) :
    size(st.world_generation.resolution),
    renderer(renderer),
    render_scale(1.0f),
    map_data(std::vector<std::vector<rgb>>(size.y, std::vector<rgb>(size.x))) {}

World::~World() { SDL_DestroyTexture(tex); }

void World::update_map(nlohmann::json new_map_data) {
    // map_data = new_map_data;
    for (auto &[y_s, row] : new_map_data.items()) {
        for (auto &[x_s, pixel] : row.items()) {
            map_data[std::stoi(y_s)][std::stoi(x_s)] = pixel;
        }
    }

    // create the map surface
    size = v2u(map_data[0].size(), map_data.size());

    // flatten 2d map_data into 1d array
    int depth = 24;
    int pitch = size.x * 3;

    std::vector<uint8_t> pixel_data(size.length() * 3);

    for (int y = 0; y < size.y; y++) {
        for (int x = 0; x < size.x; x++) {
            int index             = (y * size.x + x) * 3;
            rgb tile              = map_data[y][x];
            pixel_data[index + 0] = tile.x;
            pixel_data[index + 1] = tile.y;
            pixel_data[index + 2] = tile.z;
        }
    }

    SDL_Surface *surf = SDL_CreateRGBSurfaceWithFormatFrom(
        pixel_data.data(),
        size.x,
        size.y,
        depth,
        pitch,
        SDL_PIXELFORMAT_RGB24
    );

    tex  = SDL_CreateTextureFromSurface(renderer, surf);
    rect = {
        .x = 0,
        .y = 0,
        .w = (int)size.x,
        .h = (int)size.y,
    };

    SDL_FreeSurface(surf);
}

void World::draw(v2f scroll) {
    rect.x = scroll.x;
    rect.y = scroll.y;
    rect.w = size.x * render_scale;
    rect.h = size.y * render_scale;

    SDL_RenderCopy(renderer, tex, nullptr, &rect);
}
