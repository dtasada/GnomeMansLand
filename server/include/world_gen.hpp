#pragma once

#include "../../shared/include/engine.hpp"
#include "../../shared/include/v2.hpp"
#include "../../shared/include/v3.hpp"

#include <csignal>
#include <nlohmann/json.hpp>
#include <vector>

inline namespace Color {
    inline rgb WATER_LOW     = rgb(0, 0, 50);
    inline rgb WATER_HIGH    = rgb(30, 110, 140);
    inline rgb SAND_LOW      = rgb(237, 206, 178);
    inline rgb SAND_HIGH     = rgb(255, 245, 193);
    inline rgb GRASS_LOW     = rgb(10, 155, 104);
    inline rgb GRASS_HIGH    = rgb(0, 120, 80);
    inline rgb MOUNTAIN_LOW  = rgb(80, 80, 80);
    inline rgb MOUNTAIN_HIGH = rgb(120, 120, 120);
};

inline namespace TileData {
    inline float WATER    = 0.48f;
    inline float SAND     = 0.51;
    inline float GRASS    = 0.61f;
    inline float MOUNTAIN = 0.68f;
    inline float SNOW     = 1.f;
};

class WorldGen {
    v2u   size;
    float render_scale;

  public:
    WorldGen() = default;
    WorldGen(Settings st, nlohmann::json &db);

    std::vector<std::vector<rgb>> map_data;
};

class PerlinNoise {
  public:
    PerlinNoise(unsigned int seed);

    float noise(float x, float y, float z) const;

  private:
    std::vector<int> p; // Permutation vector

    float fade(float t) const;
    float lerp(float t, float a, float b) const;
    float grad(int hash, float x, float y, float z) const;
};
