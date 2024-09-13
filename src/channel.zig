const std = @import("std");
const testing = std.testing;
const RwLock = std.Thread.RwLock;

pub const io_mode = .evented;

const ChannelError = error{
    Full,
    Empty,
};

pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();
        mutex: RwLock = .{},
        valid: bool = false,
        content: ?T = undefined,

        pub inline fn init() Self {
            return Self{};
        }

        pub fn get(self: *Self) ?T {
            self.mutex.lockShared();
            defer self.mutex.unlockShared();
            defer self.content = null;
            while (self.valid == false) {
                std.time.sleep(10);
            }
            self.valid = false;
            return self.content;
        }

        pub fn peek(self: *Self) !?T {
            self.mutex.lockShared();
            defer self.mutex.unlockShared();
            if (self.valid == false) {
                return ChannelError.Empty;
            } else {
                return self.content;
            }
        }

        pub fn set(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            while (self.valid) {
                std.time.sleep(10);
            }
            self.content = item;
            self.valid = true;
        }

        pub fn setHard(self: *Self, item: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.content = item;
            self.valid = true;
        }

        pub fn replace(self: *Self, item: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.valid == false) return ChannelError.Empty;
            defer self.content = item;
            return self.content;
        }

        pub fn lock(self: *Self) void {
            self.mutex.lock();
        }

        pub fn unlock(self: *Self) void {
            self.mutex.unlock();
        }
    };
}

pub fn BufferedChannel(comptime T: type, size: u32) type {
    if (size == 1) @compileLog("buffered channel with size 1 not suitable, consider the simple channel");
    if (size < 1) @compileError("size of channel must be greater or equal to 1");
    return struct {
        pub const Self = @This();
        mutex: std.Thread.RwLock = .{},
        read: u8 = 0,
        write: u8 = 0,
        full: bool = false,
        content: [size]?T = undefined,

        pub fn init() Self {
            var self = Self{};
            self.content[0] = null;
            return self;
        }

        pub fn get(self: *Self) ChannelError!?T {
            if (self.read >= self.write) {
                return ChannelError.Empty;
            }
            self.mutex.lockShared();
            defer self.mutex.unlockShared();
            defer self.read = (self.read + 1) % size;
            return self.content[self.read];
        }

        pub fn peek(self: *Self) ?T {
            if (self.read >= self.write) {
                return null;
            }
            self.mutex.lockShared();
            defer self.mutex.unlockShared();
            return self.content[self.read];
        }

        pub fn add(self: *Self, item: T) ChannelError!void {
            if (self.full) {
                return ChannelError.Full;
            } else if (self.read == (self.write + 1) % size) {
                self.full = true;
            } else {
                self.mutex.lock();
                defer self.mutex.unlock();
                self.content[self.write] = item;
                self.write = (self.write + 1) % size;
            }
        }

        pub fn lock(self: *Self) void {
            self.mutex.lock();
        }

        pub fn unlock(self: *Self) void {
            self.mutex.unlock();
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.read = 0;
            self.write = 0;
            self.full = false;
        }
    };
}

fn foo(channel: *Channel(u32)) !void {
    const c = channel.get();
    if (c) |number| {
        channel.set(number + 1);
    } else {
        return ChannelError.Empty;
    }
}

fn fooo(channel: *BufferedChannel(u32, 8), apply: bool) !void {
    const c = try channel.get();
    if (c) |n| {
        if (apply) try channel.add(n + 10);
    } else {
        return ChannelError.Empty;
    }
}

test "single item" {
    var chan = Channel(u64).init();
    chan.set(5);
    try testing.expect(chan.valid);
    const ret = chan.get();
    try testing.expect(ret == 5);
}

test "multi item" {
    var chan = BufferedChannel(u64, 8).init();
    try testing.expectError(ChannelError.Empty, chan.get());
    for (0..7) |i| {
        try chan.add(i);
    }
    try testing.expect(try chan.get() == 0);
    try testing.expect(chan.peek() == 1);
    try chan.add(6);
    try chan.add(6);
    try testing.expectError(ChannelError.Full, chan.add(7));
}

test "threaded single item" {
    var chan = Channel(u32).init();
    try testing.expectError(ChannelError.Empty, chan.peek());
    chan.set(1);
    try testing.expect(try chan.peek() == 1);
    const t = try std.Thread.spawn(.{}, foo, .{&chan});
    t.join();
    try testing.expect(try chan.peek() == 2);
}

test "threaded multi item" {
    var chan = BufferedChannel(u32, 8).init();
    try chan.add(1);
    try chan.add(2);
    try chan.add(3);
    var threads: [6]std.Thread = undefined;
    for (0..6) |i| {
        threads[i] = try std.Thread.spawn(.{}, fooo, .{ &chan, i % 2 == 0 });
    }
    for (threads) |t| {
        t.join();
    }
    try testing.expectError(ChannelError.Empty, chan.get());
}

test "multi item clear" {
    var chan = BufferedChannel(u32, 8).init();
    try chan.add(1);
    try chan.add(2);
    try chan.add(3);
    chan.clear();
    try testing.expectError(ChannelError.Empty, chan.get());
}
