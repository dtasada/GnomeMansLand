#include "../../shared/include/engine.hpp"
#include "../include/sprite.hpp"

Sprite::Sprite(SDL_Renderer *renderer, std::string image_path, SDL_Rect rect, v2f vel, v2f acc) :
    rect(rect),
    vel(vel),
    acc(acc) {
    tex = IMG_LoadTexture(renderer, image_path.c_str());
    SDL_Point size;
    SDL_QueryTexture(tex, NULL, NULL, &size.x, &size.y);
}

Sprite::~Sprite() { SDL_DestroyTexture(tex); }

void Sprite::copy(SDL_Renderer *renderer) { SDL_RenderCopy(renderer, tex, NULL, &rect); }
