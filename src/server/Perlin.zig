//! Perlin noise algorithm implementation
const std = @import("std");
const Self = @This();

p: std.ArrayList(i32), // Permutation vector

pub fn init(alloc: std.mem.Allocator, seed: u32) !Self {
    var self: Self = .{ .p = try std.ArrayList(i32).initCapacity(alloc, 256) };
    try self.p.resize(alloc, 256);

    // Fill using for loop with enumerate
    for (self.p.items, 0..) |*item, index|
        item.* = @intCast(index);

    // Shuffle using the seed
    var rand = std.Random.DefaultPrng.init(seed);
    std.Random.shuffle(rand.random(), i32, self.p.items);

    // Duplicate the permutation vector
    try self.p.resize(alloc, 512);
    @memcpy(self.p.items[256..512], self.p.items[0..256]);

    return self;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.p.deinit(alloc);
}

pub fn noise(self: *const Self, x: f32, y: f32, z: f32) f32 {
    // Find the unit cube that contains the point
    const X: i32 = @as(i32, @intFromFloat(@floor(x))) & 255;
    const Y: i32 = @as(i32, @intFromFloat(@floor(y))) & 255;
    const Z: i32 = @as(i32, @intFromFloat(@floor(z))) & 255;

    // Find relative x, y, z of point in cube
    const x_rel = x - @floor(x);
    const y_rel = y - @floor(y);
    const z_rel = z - @floor(z);

    // Compute fade curves for each of x, y, z
    const u = fade(x_rel);
    const v = fade(y_rel);
    const w = fade(z_rel);

    // Hash coordinates of the 8 cube corners
    const A = self.p.items[@intCast(X)] + Y;
    const AA = self.p.items[@intCast(A)] + Z;
    const AB = self.p.items[@intCast(A + 1)] + Z;
    const B = self.p.items[@intCast(X + 1)] + Y;
    const BA = self.p.items[@intCast(B)] + Z;
    const BB = self.p.items[@intCast(B + 1)] + Z;

    // Add blended results from 8 corners of cube
    return lerp(
        w,
        lerp(v, lerp(u, grad(self.p.items[@intCast(AA)], x_rel, y_rel, z_rel), grad(self.p.items[@intCast(BA)], x_rel - 1, y_rel, z_rel)), lerp(u, grad(self.p.items[@intCast(AB)], x_rel, y_rel - 1, z_rel), grad(self.p.items[@intCast(BB)], x_rel - 1, y_rel - 1, z_rel))),
        lerp(
            v,
            lerp(u, grad(self.p.items[@intCast(AA + 1)], x_rel, y_rel, z_rel - 1), grad(self.p.items[@intCast(BA + 1)], x_rel - 1, y_rel, z_rel - 1)),
            lerp(
                u,
                grad(self.p.items[@intCast(AB + 1)], x_rel, y_rel - 1, z_rel - 1),
                grad(self.p.items[@intCast(BB + 1)], x_rel - 1, y_rel - 1, z_rel - 1),
            ),
        ),
    );
}

fn fade(t: f32) f32 {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

fn lerp(t: f32, a: f32, b: f32) f32 {
    return a + t * (b - a);
}

fn grad(hash: i32, x: f32, y: f32, z: f32) f32 {
    const h: i32 = hash & 15;
    const u: f32 = if (h < 8) x else y;
    const v: f32 = if (h < 4) y else (if (h == 12 or h == 14) x else z);
    return (if (h & 1 != 0) -u else u) + (if (h & 2 != 0) -v else v);
}
