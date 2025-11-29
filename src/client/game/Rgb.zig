const Self = @This();

r: i16,
g: i16,
b: i16,

pub fn init(r: i16, g: i16, b: i16) Self {
    return .{ .r = r, .g = g, .b = b };
}

fn add(lhs: Self, rhs: Self) Self {
    return Self.init(lhs.r + rhs.r, lhs.g + rhs.g, lhs.b + rhs.b);
}

fn subtract(lhs: Self, rhs: Self) Self {
    return Self.init(lhs.r -| rhs.r, lhs.g -| rhs.g, lhs.b -| rhs.b);
}

fn scale(lhs: Self, m: f32) Self {
    const m_ = @max(m, 0.0);
    return Self.init(
        @intFromFloat(@as(f32, @floatFromInt(lhs.r)) * m_),
        @intFromFloat(@as(f32, @floatFromInt(lhs.g)) * m_),
        @intFromFloat(@as(f32, @floatFromInt(lhs.b)) * m_),
    );
}

pub fn lerp(lhs: Self, rhs: Self, m: f32) Self {
    return lhs.add(rhs.subtract(lhs).scale(m));
}
