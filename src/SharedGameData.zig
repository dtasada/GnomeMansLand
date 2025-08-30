pub const Player = struct {
    const Self = @This();

    nickname: []const u8,

    pub fn init(nickname: []const u8) Self {
        return .{ .nickname = nickname };
    }
};
