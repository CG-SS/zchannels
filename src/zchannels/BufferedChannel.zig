const std = @import("std");
const Testing = std.testing;
const Allocator = std.mem.Allocator;
const StaticQueue = @import("StaticQueue.zig").StaticQueue;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

pub const BufferedChanelError = error{
    Closed,
};

pub fn BufferedChannel(comptime T: type) type {
    return struct {
        queue: StaticQueue(T),
        sharedMutex: Mutex = .{},
        writeCondition: Condition = .{},
        readCondition: Condition= .{},
        closed: bool = false,
        numWaitingWrite: usize = 0,
        numWaitingRead: usize = 0,

        pub fn init(allocator: Allocator, capacity: usize) !BufferedChannel(T) {
            return .{
                .queue = try StaticQueue(T).init(allocator, capacity),
            };
        }

        pub fn deinit(self: BufferedChannel(T)) void {
            self.queue.deinit();
        }

        pub fn isClosed(self: *BufferedChannel(T)) bool {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            return self.closed;
        }

        pub fn send(self: *BufferedChannel(T), data: T) !void {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            if (self.closed) {
                return BufferedChanelError.Closed;
            }

            while(self.queue.isFull()) {
                self.numWaitingWrite += 1;
                self.writeCondition.wait(&self.sharedMutex);
                self.numWaitingWrite -= 1;
            }

            const result = self.queue.push(data);

            if(self.numWaitingRead > 0){
                self.readCondition.signal();
            }

            return result;
        }

        pub fn receive(self: *BufferedChannel(T)) !T {
            self.sharedMutex.lock();
            defer self.sharedMutex.unlock();

            if (self.closed) {
                return BufferedChanelError.Closed;
            }

            while (self.queue.isEmpty()) {
                self.numWaitingRead += 1;
                self.readCondition.wait(&self.sharedMutex);
                self.numWaitingRead -= 1;
            }

            const result = self.queue.pop();

            if (self.numWaitingWrite > 0) {
                self.writeCondition.signal();
            }

            return result;
        }

        pub fn close(self: *BufferedChannel(T)) void {
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

test "send" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    try channel.send(1);
}

test "receive" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    try channel.send(10);

    const val = try channel.receive();

    try Testing.expect(val == 10);
}

test "fails sending after closing" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    channel.close();

    try Testing.expectError(BufferedChanelError.Closed, channel.send(1));
}

test "fails receiving after closing" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    channel.close();

    try Testing.expectError(BufferedChanelError.Closed, channel.receive());
}

test "sends and receives a value" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    try channel.send(125);

    const val = try channel.receive();

    try Testing.expect(val == 125);
}

test "sends and receives multiple values" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 3);
    defer channel.deinit();

    try channel.send(1);
    try channel.send(2);
    try channel.send(3);

    const val1 = try channel.receive();
    const val2 = try channel.receive();
    const val3 = try channel.receive();

    try Testing.expect(val1 == 1);
    try Testing.expect(val2 == 2);
    try Testing.expect(val3 == 3);
}

test "sends and receives a value in another thread" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    const consume = struct {
        fn f(syncChannel: *BufferedChannel(u8)) !void {
            const received1 = try syncChannel.receive();
            const received2 = try syncChannel.receive();
            const received3 = try syncChannel.receive();

            try Testing.expect(received1 == 4);
            try Testing.expect(received2 == 5);
            try Testing.expect(received3 == 6);
        }
    }.f;

    const thr = try std.Thread.spawn(.{}, consume, .{&channel});

    try channel.send(4);
    try channel.send(5);
    try channel.send(6);

    thr.join();
}

test "check if close" {
    var channel = try BufferedChannel(u8).init(Testing.allocator, 1);
    defer channel.deinit();

    channel.close();

    try Testing.expect(channel.isClosed() == true);
}