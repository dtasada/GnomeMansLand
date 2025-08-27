#pragma once

#if defined(__linux)
#    include <SDL2/SDL_image.h>
#    include <SDL2/SDL_net.h>
#elif defined(__APPLE__) || defined(_WIN32)
#    include <SDL_image.h>
#    include <SDL_net.h>
#endif

#ifdef _WIN32
#    include <SDL.h>
#else
#    include <SDL2/SDL.h>
#endif

#include "../../shared/include/v2.hpp"
#include "../../shared/include/v3.hpp"

#include <cstdint>
#include <iostream>
#include <string>
#include <toml++/toml.hpp>

rgb     lerp_color(rgb c1, rgb c2, float m);
int64_t randint64(int64_t min, int64_t max);
float   rand01();

struct Settings {
    struct {
        v2u      resolution       = v2u(1280, 720);
        uint16_t target_framerate = 60;
    } video;

    struct {
        std::string server_host             = "127.0.0.1";
        uint16_t    server_port             = 4444;
        uint32_t    server_polling_interval = 200;
    } multiplayer;

    struct {
        v2u      resolution  = v2u(800, 800);
        uint32_t seed        = randint64(0, UINT32_MAX);
        int      octaves     = 10;
        float    persistence = 0.5f;
        float    lacunarity  = 2.0f;
        float    frequency   = 0.003f;
    } world_generation;

    struct {
        uint16_t port = 2000;
    } server;

    static Settings parse() {
        Settings settings;

        try {
            toml::table settings_t = toml::parse_file("settings.toml");

            if (!settings_t.empty()) {
                settings = {
					.video = {
						.resolution = v2u(
							settings_t["video"]["resolution"][0].value_or(settings.video.resolution.x),
							settings_t["video"]["resolution"][1].value_or(settings.video.resolution.y)
						),
					},
					.multiplayer = {
						.server_host = settings_t["multiplayer"]["server_host"].value_or(settings.multiplayer.server_host),
						.server_port = settings_t["multiplayer"]["server_port"].value_or(settings.multiplayer.server_port),
						.server_polling_interval = settings_t["multiplayer"]["server_polling_interval"].value_or(settings.multiplayer.server_polling_interval),
					},
					.world_generation = {
						.resolution = v2u(
							settings_t["world_generation"]["resolution"][0].value_or(settings.world_generation.resolution.x),
							settings_t["world_generation"]["resolution"][1].value_or(settings.world_generation.resolution.y)
						),
						.seed = settings_t["world_generation"]["seed"].value_or(settings.world_generation.seed),
						.octaves = settings_t["world_generation"]["octaves"].value_or(settings.world_generation.octaves),
						.persistence = settings_t["world_generation"]["persistence"].value_or(settings.world_generation.persistence),
						.lacunarity = settings_t["world_generation"]["lacunarity"].value_or(settings.world_generation.lacunarity),
						.frequency = settings_t["world_generation"]["frequency"].value_or(settings.world_generation.frequency),
					},
					.server {
						.port = settings_t["server"]["port"].value_or(settings.server.port),
					},
				};
            }

        } catch (const toml::parse_error &err) {
            std::cerr << "Failed to parse config file: " << err.what() << std::endl;
        }

        return settings;
    }
};
