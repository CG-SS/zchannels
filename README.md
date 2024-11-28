# zchannels

`zchannels` is a Zig library that implements channels similar to the ones found in Golang. Channels are a powerful synchronization primitive that allows communication between thread. This library provides a similar abstraction for concurrency in Zig, enabling safe and efficient communication between tasks.

## Features

- **Channel Types**: Supports unbuffered and buffered channels.
- **Concurrency**: Implements the core behavior of Golang-like channels in Zig to facilitate concurrent programming.
- **Task Synchronization**: Makes it easier to send and receive data between different tasks, making the code cleaner and more understandable.
- **Zero-cost abstraction**: The implementation leverages Zig's performance-focused nature to provide concurrency primitives with minimal overhead.

## Installation

To use `zchannels` in your Zig project, simply clone the repository and include the relevant files or add it as a Git submodule.

```bash
git clone https://github.com/CG-SS/zchannels.git
```

## Usage

You can check out the tests located under each implementation:

### BufferedChannel

Buffered channels allows you to send a message without blocking. Notice that they will allocate an internal buffer, so 
you need to call `deinit()` to dealloc the used memory.

```zig
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
```

### SyncChannel

Synced channels block when sending a message. The thread will hang until a receiver is ready to receive its message. 
One advantage is that there's no memory allocation required.

```zig
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
```