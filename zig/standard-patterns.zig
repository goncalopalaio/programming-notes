const std = @import("std");
const debug = std.debug.print;

pub fn main() !void {
    // Allocators

    try page_allocator();
    try fixed_buffer_allocator();
    try arena_allocator();
    try alloc_free_create_destroy();
    try general_purpose_allocator();
    // There's also a special std.testing.allocator for tests.

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;
    defer {
        const leaked = gpa.deinit();
        std.debug.assert(!leaked);
    }

    try file_system();
    try arraylist(allocator);
    try readers_and_writers(allocator);
    // try reading_user_input(allocator);
    try implementing_a_writer(allocator);
    try string_formatting(allocator);
    try custom_formatting(allocator);
    try parsing_json(allocator);
}

const Place = struct { lat: f32, lon: f32 };

fn parsing_json(allocator: *std.mem.Allocator) !void {
    var stream = std.json.TokenStream.init(
        \\ { "lat": 40.99, "lon": -74.44 }
    );

    const x = try std.json.parse(Place, &stream, .{});

    debug("\t {} {}\n", .{ x.lat, x.lon });

    // Using stringify to turn data into a string:

    const y = Place{ .lat = 51.99, .lon = -0.9 };

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(y, .{}, string.writer());

    debug("\t stringify: {s}\n", .{string.items});

    // TODO using json parser with strings, array and map (which requires an allocator).
}

fn string_formatting(allocator: *std.mem.Allocator) !void {
    debug("running string_formatting\n", .{});

    // d   - decimal number
    // s   - string
    // any - default formatting

    const string = try std.fmt.allocPrint(allocator, "{d} + {d} = {d}", .{ 9, 10, 19 });
    defer allocator.free(string);

    std.debug.assert(std.mem.eql(u8, string, "9 + 10 = 19"));

    // Writers also have a print method that allows formatting:

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.writer().print("{} + {} = {}", .{ 9, 10, 19 });

    std.debug.assert(std.mem.eql(u8, list.items, "9 + 10 = 19"));

    const out = std.io.getStdOut();
    try out.writer().print("\tHello {s}!\n", .{"World"});

    const using_any = try std.fmt.allocPrint(allocator, "{any} + {any} = {any}", .{
        @as([]const u8, &[_]u8{ 1, 4 }),
        @as([]const u8, &[_]u8{ 2, 5 }),
        @as([]const u8, &[_]u8{ 3, 9 }),
    });
    defer allocator.free(using_any);

    std.debug.assert(std.mem.eql(u8, using_any, "{ 1, 4 } + { 2, 5 } = { 3, 9 }"));
}

// Custom formatting by implementing a format function.
const Person = struct {
    name: []const u8,
    birth_year: i32,

    pub fn format(self: Person, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s} ({})", .{ self.name, self.birth_year });
    }
};

fn custom_formatting(allocator: *std.mem.Allocator) !void {
    debug("running custom_formatting\n", .{});
    // To implement formatting, implement a format function for the struct.

    const freya = Person{ .name = "Freya", .birth_year = 1970 };

    debug("\t{s}\n", .{freya});
}

const MyByteList = struct {
    data: [100]u8 = undefined,
    items: []u8 = &[_]u8{},

    const Writer = std.io.Writer(*MyByteList, error{EndOfBuffer}, appendWrite);

    fn appendWrite(self: *MyByteList, data: []const u8) error{EndOfBuffer}!usize {
        if (self.items.len + data.len > self.data.len) return error.EndOfBuffer;

        std.mem.copy(u8, self.data[self.items.len..], data);

        self.items = self.data[0 .. self.items.len + data.len];

        return data.len;
    }

    fn writer(self: *MyByteList) Writer {
        return .{ .context = self };
    }
};

fn implementing_a_writer(allocator: *std.mem.Allocator) !void {
    debug("running implementing_a_writer\n", .{});

    // You should use an arraylist with a fixed buffer allocator for this but as an example:

    debug("\t using a custom writer\n", .{});
    var bytes = MyByteList{};
    _ = try bytes.writer().write("Hello");
    _ = try bytes.writer().write(" Writer!");
    std.debug.assert(std.mem.eql(u8, bytes.items, "Hello Writer!"));
}

fn readers_and_writers(allocator: *std.mem.Allocator) !void {
    // std.io.Writer and std.io.Reader provide standard ways of making use of IO.
    // std.ArrayList(u8) has a writer method which give us a writer. Using it as an example:
    debug("running readers_and_writers\n", .{});

    var another_list = std.ArrayList(u8).init(allocator);
    defer another_list.deinit();

    const another_bytes_written = try another_list.writer().write(
        "Hello World!",
    );

    std.debug.assert(another_bytes_written == 12);
    std.debug.assert(std.mem.eql(u8, another_list.items, "Hello World!"));

    // IO reader example:

    const message = "Hello File!";

    const file = try std.fs.cwd().createFile("test-files/junk-file.txt", .{ .read = true });
    defer file.close();

    try file.writeAll(message);
    try file.seekTo(0);

    const allowed_to_allocate_max = message.len;
    const contents = try file.reader().readAllAlloc(allocator, allowed_to_allocate_max);
    // If the file is larger than the max it will return error.StreamTooLong.
    defer allocator.free(contents);

    std.debug.assert(std.mem.eql(u8, contents, message));
}

fn reading_user_input(allocator: *std.mem.Allocator) !void {
    debug("running reading_user_input\n", .{});

    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    try stdout.writeAll(
        \\ Enter your name:
    );

    var buffer: [100]u8 = undefined;
    const input = (try nextLine(stdin.reader(), &buffer)).?;
    try stdout.writer().print("Your name is: \"{s}\"\n", .{input});
}

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    var line = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;

    // Trimming windows-only carriage return character:
    if (std.builtin.Target.current.os.tag == .windows) {
        line = std.mem.trimRight(u8, line, "\r");
    }

    return line;
}

fn arraylist(allocator: *std.mem.Allocator) !void {
    debug("running arraylist\n", .{});

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    try list.append('H');
    try list.append('e');
    try list.append('l');
    try list.append('l');
    try list.append('o');
    try list.appendSlice(" World!");

    std.debug.assert(std.mem.eql(u8, list.items, "Hello World!"));
}

fn file_system() !void {
    debug("running file_system\n", .{});

    const file = try std.fs.cwd().createFile("test-files/test.txt", .{ .read = true });
    defer file.close();
    // std.fs.openFileAbsolute also exists.

    const bytes_written = try file.writeAll("Hello!!!!");

    var buffer: [100]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);

    std.debug.assert(std.mem.eql(u8, buffer[0..bytes_read], "Hello!!!!"));

    // You can use stat() to get file information:
    const stat = try file.stat();
    debug("\tstat: {} {} {} {} {}\n", .{ stat.size, stat.kind, stat.ctime, stat.mtime, stat.atime });

    std.debug.assert(stat.kind == .File);
    std.debug.assert(stat.ctime <= std.time.nanoTimestamp());

    // Making directories and iterating over their contents:
    try std.fs.cwd().makeDir("test-tmp");
    const dir = try std.fs.cwd().openDir("test-tmp", .{ .iterate = true });
    defer {
        std.fs.cwd().deleteTree("test-tmp") catch unreachable;
    }

    _ = try dir.createFile("x", .{});
    _ = try dir.createFile("y", .{});
    _ = try dir.createFile("z", .{});

    // Using iterators here. Explained later.
    var file_count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .File) file_count += 1;
    }

    std.debug.assert(file_count == 3);
}
fn page_allocator() !void {
    debug("running page_allocator\n", .{});

    // Asks the OS for entire pages of memory; an allocation of a single byte will likely reserve multiple kibibytes.
    // As asking the OS for memory requires a system call this is also extremely inefficient for speed.
    const allocator = std.heap.page_allocator;

    const memory = try allocator.alloc(u8, 100);
    defer allocator.free(memory);

    debug("\tExpected to have a []u8 with 100 elements: {} {}\n", .{ @TypeOf(memory), memory.len });
}

fn general_purpose_allocator() !void {
    debug("running general_purpose_allocator\n", .{});

    // The standard library includes a general purpose allocator.
    // This is a safe allocator which can prevent double-free, use-after-free and can detect leaks.
    // The security features can be turned off by the configuration struct (left empty below).
    // It's designed for safety over performance but may still be many times faster than page_allocator.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        std.debug.assert(!leaked);
    }

    const bytes = try gpa.allocator.alloc(u8, 100);
    defer gpa.allocator.free(bytes);

    // For high performance but very few safety features std.heap.c_allocator can be also considered but you need to link with libc (with -lc)
}

fn fixed_buffer_allocator() !void {
    debug("running fixed_buffer_allocator\n", .{});

    // Allocators memory into a fixed buffer and does not make any heap allocations.
    // Useful for when heap usage is not wanted - for example when writing a kernel or for performance considerations reasons.
    // It will give OutOfMemory if it has run of bytes.
    var buffer: [1000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    var allocator = &fba.allocator;

    const memory = try allocator.alloc(u8, 100);
    defer allocator.free(memory);

    debug("\tExpected to have a []u8 with 100 elements: {} {}\n", .{ @TypeOf(memory), memory.len });
}

fn arena_allocator() !void {
    debug("running arena_allocator\n", .{});

    // Takes a child allocator and allows you to allocate many times and only free once (deinit()).
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = &arena.allocator;

    const m1 = try allocator.alloc(u8, 1);
    const m2 = try allocator.alloc(u8, 10);
    const m3 = try allocator.alloc(u8, 100);
}

fn alloc_free_create_destroy() !void {
    debug("running alloc_free_create_destroy\n", .{});

    // alloc and free are used for slices. For single items use create and destroy.
    const byte = try std.heap.page_allocator.create(u8);
    defer std.heap.page_allocator.destroy(byte);
    byte.* = 128;
}