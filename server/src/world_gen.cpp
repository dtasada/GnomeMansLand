#include "../../shared/include/engine.hpp"
#include "../include/world_gen.hpp"

#include <iostream>
#include <nlohmann/json.hpp>
#include <omp.h>

WorldGen::WorldGen(Settings st, nlohmann::json &db) : size(st.world_generation.resolution) {
    map_data     = std::vector<std::vector<rgb>>(size.y, std::vector<rgb>(size.x));
    render_scale = 1.0f;

    uint32_t seed = st.world_generation.seed;
    std::cout << "Seed: " << seed << std::endl;
    PerlinNoise pn(seed);

#pragma omp parallel for collapse(2)
    for (int y = 0; y < size.y; y++) {
        for (int x = 0; x < size.x; x++) {
            // get the terrain generation data form the settings file
            float freq      = 7.68f * st.world_generation.frequency / size.x;
            float height    = 0.0f;
            float amp       = 1.0f;
            float max_value = 0.0f;

            // calculate the noise octaves
            float nx, ny;
            for (int i = 0; i < st.world_generation.octaves; i++) {
                nx = x * (freq * 1);
                ny = y * (freq * 1);

                height += amp * pn.noise(nx, ny, 0);

                max_value += amp;
                amp *= st.world_generation.persistence;
                freq *= st.world_generation.lacunarity;
            }
            // normalize total height to (0, 1)
            height = (height + max_value) / (max_value * 2);

            // create linearly interpolated colors for terrain
            rgb tile;

            if (height <= TileData::WATER) {
                tile = lerp_color(Color::WATER_LOW, Color::WATER_HIGH, height / TileData::WATER);
            } else if (height <= TileData::SAND) {
                tile = lerp_color(
                    Color::SAND_LOW,
                    Color::SAND_HIGH,
                    (height - TileData::WATER) / (TileData::SAND - TileData::WATER)
                );
            } else if (height <= TileData::GRASS) {
                tile = lerp_color(
                    Color::GRASS_LOW,
                    Color::GRASS_HIGH,
                    (height - TileData::SAND) / (TileData::GRASS - TileData::SAND)
                );
            } else if (height <= TileData::MOUNTAIN) {
                tile = lerp_color(
                    Color::MOUNTAIN_LOW,
                    Color::MOUNTAIN_HIGH,
                    (height - TileData::GRASS) / (TileData::MOUNTAIN - TileData::GRASS)
                );
            } else {
                tile = rgb(240, 240, 240);
            }

            // set the data
            map_data[y][x] = tile;
        }
    }

    db["world"]["map_data"] = map_data;

    std::clog << "World generated" << std::endl;
}
