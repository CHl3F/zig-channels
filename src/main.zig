const std = @import("std");

const channel = @import("channel.zig");

fn handle(c: *channel.Channel(u32)) void {
    for (0..100) |_| {
        const v = c.get();
        if (v) |value| {
            c.set((value * 2) % 2147483648);
        } else {
            @panic("received empty channel");
        }
    }
}

pub fn main() !void {
    var chan = channel.Channel(u32).init();
    var t = try std.Thread.spawn(.{}, handle, .{&chan});
    chan.set(2);
    for (0..100) |_| {
        const v = chan.get();
        if (v) |value| {
            chan.set((value * 2) % 2147483648);
        } else {
            @panic("received empty channel");
        }
    }
    t.join();
}
