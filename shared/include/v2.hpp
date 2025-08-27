#pragma once

#include <cstdint>
#include <ostream>

template<typename T> struct v2 {
    T x, y;

    // clang-format off
    v2(T x, T y) : x(x), y(y) {}
    v2(T v) : x(v), y(v) {}
    v2(void) : v2(0) {}

    v2 operator+(const v2 &rhs) const { return v2(x + rhs.x, y + rhs.y); }
    v2 operator-(const v2 &rhs) const { return v2(x - rhs.x, y - rhs.y); }
    v2 operator*(const v2 &rhs) const { return v2(x * rhs.x, y * rhs.y); }
    v2 operator/(const v2 &rhs) const { return v2(x / rhs.x, y / rhs.y); }
    v2 operator+=(const v2 &rhs) { return *this = *this + rhs; }
    v2 operator-=(const v2 &rhs) { return *this = *this - rhs; }
    v2 operator*=(const v2 &rhs) { return *this = *this * rhs; }
    v2 operator/=(const v2 &rhs) { return *this = *this / rhs; }
    v2 operator-(const T &rhs) const { return v2(x - rhs, y - rhs); }
    v2 operator+(const T &rhs) const { return v2(x + rhs, y + rhs); }
    v2 operator*(const T &rhs) const { return v2(x * rhs, y * rhs); }
    v2 operator/(const T &rhs) const { return v2(x / rhs, y / rhs); }
    v2 operator*=(const T &rhs) { return *this = *this * rhs; }
    v2 operator/=(const T &rhs) { return *this = *this / rhs; }
    v2 operator+=(const T &rhs) { return *this = *this + rhs; }
    v2 operator-=(const T &rhs) { return *this = *this - rhs; }
    bool operator==(const v2 &rhs) const { return x == rhs.x && y == rhs.y; }
    bool operator!=(const v2 &rhs) const { return !(*this == rhs); }

    // clang-format on

    operator T *() const { return new T[3]{x, y}; }

  public:
    float length() const { return x * y; }

    friend std::ostream &operator<<(std::ostream &os, const v2 &v) {
        os << "v2(" << v.x << ", " << v.y << ")";
        return os;
    }
};

typedef v2<float>    v2f;
typedef v2<int32_t>  v2i;
typedef v2<uint32_t> v2u;
