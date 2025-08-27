#include "../include/engine.hpp"
#include "../include/v3.hpp"

#include <random>

// functions
int64_t randint64(int64_t a, int64_t b) {
    std::random_device rd;
    std::mt19937_64    gen(rd());

    std::uniform_int_distribution<int64_t> dis(a, b);
    return dis(gen);
}

float rand01() {
    std::random_device rd;
    std::mt19937       gen(rd());

    std::uniform_real_distribution<> dis(0.0, 1.0);
    return dis(gen);
}

rgb lerp_color(rgb c1, rgb c2, float m) { return (v3f)(c1) + ((v3f)c2 - (v3f)c1) * m; }
