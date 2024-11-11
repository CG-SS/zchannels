const std = @import("std");
const Testing = std.testing;
const Allocator = std.mem.Allocator;
const StaticQueue = @import("StaticQueue.zig").StaticQueue;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

const BufferedChanelError = error{
    Closed,
};

fn BufferedChannel(comptime T: type) type {
    return struct {
        queue: StaticQueue(T),
        sharedMutex: Mutex = .{},
        writeCondition: Condition = .{},
        readCondition: Condition= .{},
        closed: bool = false,
        numWaitingWrite: usize = 0,
        numWaitingRead: usize = 0,

        fn init(allocator: Allocator, capacity: usize) !BufferedChannel(T) {
            return .{
                .queue = try StaticQueue(T).init(allocator, capacity),
            };
        }

        fn deinit(self: BufferedChannel(T)) void {
            self.queue.deinit();
        }

        fn send(self: *BufferedChannel(T), data: T) !void {
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

        fn receive(self: *BufferedChannel(T)) !T {
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

        fn close(self: *BufferedChannel(T)) void {
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