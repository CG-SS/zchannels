const std = @import("std");
const Testing = std.testing;
const Allocator = std.mem.Allocator;

const QueueError = error{
    NoCapacity,
    Empty,
};

fn StaticQueue(comptime T: type) type {
    return struct {
        size: usize,
        next: usize,
        capacity: usize,
        items: []T,
        allocator: Allocator,

        fn isFull(self: StaticQueue(T)) bool {
            return self.size >= self.capacity;
        }

        fn isEmpty(self: StaticQueue(T)) bool {
            return self.size == 0;
        }

        fn init(allocator: Allocator, capacity: usize) !StaticQueue(T) {
            return .{
                .allocator = allocator,
                .size = 0,
                .next = 0,
                .capacity = capacity,
                .items = try allocator.alloc(T, capacity),
            };
        }

        fn deinit(self: StaticQueue(T)) void {
            self.allocator.free(self.items);
        }

        fn push(self: *StaticQueue(T), value: T) !void {
            if (self.isFull()) {
                return QueueError.NoCapacity;
            }

            var pos = self.next + self.size;
            if (pos >= self.capacity) {
                pos -= self.capacity;
            }

            self.items[pos] = value;
            self.size += 1;
        }

        fn pop(self: *StaticQueue(T)) !T {
            if(self.size == 0) {
                return QueueError.Empty;
            }

            const value = self.items[self.next];
            self.next += 1;
            self.size -= 1;
            if (self.next >= self.capacity){
                self.next -= self.capacity;
            }

            return value;
        }
    };
}

test "pop empty error" {
    var queue = try StaticQueue(u8).init(Testing.allocator, 1);
    defer queue.deinit();

    try Testing.expectError(QueueError.Empty, queue.pop());
}

test "push no capacity error" {
    var queue = try StaticQueue(u8).init(Testing.allocator, 1);
    defer queue.deinit();

    try queue.push(1);
    try Testing.expectError(QueueError.NoCapacity, queue.push(2));
}

test "is full" {
    var queue = try StaticQueue(u8).init(Testing.allocator, 1);
    defer queue.deinit();

    try queue.push(1);
    try Testing.expect(queue.isFull());
}

test "is empty" {
    var queue = try StaticQueue(u8).init(Testing.allocator, 1);
    defer queue.deinit();

    try Testing.expect(queue.isEmpty());
}

test "push" {
    var queue = try StaticQueue(u8).init(Testing.allocator, 1);
    defer queue.deinit();

    try queue.push(1);

    try Testing.expect(queue.items[0] == 1);
}

test "pop" {
    var queue = try StaticQueue(u8).init(Testing.allocator, 1);
    defer queue.deinit();

    try queue.push(5);

    const val = try queue.pop();
    try Testing.expect(val == 5);
}