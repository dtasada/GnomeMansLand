#include "../../shared/include/v2.hpp"

#include <SDL2/SDL_rect.h>
#include <SDL2/SDL_render.h>
#include <string>

struct Sprite {
    SDL_Texture *tex;
    SDL_Rect     rect;
    v2f          vel, acc;

    Sprite(
        SDL_Renderer *renderer,
        std::string   image_path,
        SDL_Rect      rect,
        v2f           vel = {0, 0},
        v2f           acc = {0, 0}
    );

    ~Sprite(void);

    void copy(SDL_Renderer *);
};
