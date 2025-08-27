#pragma once

#include <cstdint>
#include <iostream>
#include <nlohmann/json.hpp>
#include <ostream>

template<typename T> struct v3 {
    T x, y, z;

    // clang-format off
    v3(T x, T y, T z) : x(x), y(y), z(z) {}
    v3(T v) : x(v), y(v), z(v) {}
    v3(void) : v3(0) {}
	template<typename U>
	v3(const v3<U>& other) :
		x(static_cast<T>(other.x)), 
		y(static_cast<T>(other.y)), 
		z(static_cast<T>(other.z)) {}


    v3 operator+(const v3 &rhs) const { return v3(x + rhs.x, y + rhs.y, z + rhs.z); }
    v3 operator-(const v3 &rhs) const { return v3(x - rhs.x, y - rhs.y, z - rhs.z); }
    v3 operator*(const v3 &rhs) const { return v3(x * rhs.x, y * rhs.y, z * rhs.z); }
    v3 operator/(const v3 &rhs) const { return v3(x / rhs.x, y / rhs.y, z / rhs.z); }
    v3 operator+=(const v3 &rhs) { return *this = *this + rhs; }
    v3 operator-=(const v3 &rhs) { return *this = *this - rhs; }
    v3 operator*=(const v3 &rhs) { return *this = *this * rhs; }
    v3 operator/=(const v3 &rhs) { return *this = *this / rhs; }
    v3 operator-(const T &rhs) const { return v3(x - rhs, y - rhs, z - rhs); }
    v3 operator+(const T &rhs) const { return v3(x + rhs, y + rhs, z + rhs); }
    v3 operator*(const T &rhs) const { return v3(x * rhs, y * rhs, z * rhs); }
    v3 operator/(const T &rhs) const { return v3(x / rhs, y / rhs, z / rhs); }
    v3 operator*=(const T &rhs) { return *this = *this * rhs; }
    v3 operator/=(const T &rhs) { return *this = *this / rhs; }
    v3 operator+=(const T &rhs) { return *this = *this + rhs; }
    v3 operator-=(const T &rhs) { return *this = *this - rhs; }
    bool operator==(const v3 &rhs) const { return x == rhs.x && y == rhs.y && z == rhs.z; }
    bool operator!=(const v3 &rhs) const { return !(*this == rhs); }
	T &operator[](int i) { return i == 0 ? x : i == 1 ? y : z; }

    // clang-format on

    operator T *() const { return new T[3]{x, y, z}; }


  public:
    float length() const { return x * y * z; }

    friend std::ostream &operator<<(std::ostream &os, const v3 &v) {
        os << "v3(" << (int)v.x << ", " << (int)v.y << ", " << (int)v.z << ")";
        return os;
    }

    friend void to_json(nlohmann::json &j, const v3 &vec) {
        j = nlohmann::json{vec.x, vec.y, vec.z};
    }

    friend void from_json(const nlohmann::json &j, v3 &vec) {
        vec.x = j.at(0);
        vec.y = j.at(1);
        vec.z = j.at(2);
    }
};

typedef v3<float>    v3f;
typedef v3<int32_t>  v3i;
typedef v3<uint32_t> v3u;
typedef v3<uint8_t>  rgb;
