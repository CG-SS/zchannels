const std = @import("std");
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;
const Allocator = std.mem.Allocator;
const Testing = std.testing;

pub const SyncChannelError = error{
    Closed,
};

pub fn SyncChannel(comptime T: type) type {
    return struct {
        writeMutex: Mutex = .{},
        readMutex: Mutex = .{},
        sharedMutex: Mutex = .{},
        writeCondition: Condition = .{},
        readCondition: Condition= .{},
        closed: bool = false,
        numWaitingWrite: usize = 0,
        numWaitingRead: usize = 0,
        data: ?T = null,

        pub fn init() SyncChannel(T) {
            return .{};
        }

        pub fn isClosed(self: *SyncChannel(T)) bool {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            return self.closed;
        }

        pub fn send(self: *SyncChannel(T), data: T) !void {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            if (self.closed) {
                return SyncChannelError.Closed;
            }

            self.writeMutex.lock();
            defer self.writeMutex.unlock();

            self.data = data;
            self.numWaitingWrite += 1;

            if(self.numWaitingRead > 0) {
                self.readCondition.signal();
            }

            self.writeCondition.wait(&self.sharedMutex);
        }

        pub fn receive(self: *SyncChannel(T)) !T {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            if (self.closed) {
                return SyncChannelError.Closed;
            }

            self.readMutex.lock();
            defer self.readMutex.unlock();

            while (self.numWaitingWrite == 0) {
                self.numWaitingRead += 1;
                self.readCondition.wait(&self.sharedMutex);
                self.numWaitingRead -= 1;
            }

            const data = self.data;

            self.numWaitingWrite -= 1;
            self.writeCondition.signal();

            return data.?;
        }

        pub fn close(self: *SyncChannel(T)) void {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            if(self.closed) {
                return;
            }

            self.closed = true;
            self.writeCondition.broadcast();
            self.readCondition.broadcast();
        }
    };
}

test "send and receive" {
    var channel = SyncChannel(u8).init();
    defer channel.close();

    const consume = struct {
        fn f(syncChannel: *SyncChannel(u8)) !void {
            const received1 = try syncChannel.receive();
            const received2 = try syncChannel.receive();

            try Testing.expect(received1 == 177);
            try Testing.expect(received2 == 200);
        }
    }.f;

    const thr = try std.Thread.spawn(.{}, consume, .{&channel});

    try channel.send(177);
    try channel.send(200);
    thr.join();
}

test "send fails if closed" {
    var channel = SyncChannel(u8).init();
    channel.close();

    try Testing.expectError(SyncChannelError.Closed, channel.send(1));
}

test "receive fails if closed" {
    var channel = SyncChannel(u8).init();
    channel.close();

    try Testing.expectError(SyncChannelError.Closed, channel.receive());
}

test "check if close" {
    var channel = SyncChannel(u8).init();
    channel.close();

    try Testing.expect(channel.isClosed() == true);
}