const std = @import("std");
const builtin = @import("builtin");
const INode = @import("INode.zig").INode;
const Timestamp = @import("INode.zig").Timestamp;

const FileOpenError = error{
    AccessDenied,
    FileNotFound,
};

/// FileSystemTree is a file system implementation that uses a hash table to store
/// file data. It is designed to be used in a WebAssembly environment.
/// It is required to call .destroy() on it to free the memory
pub const FileSystemTree = struct {
    root: *INode,
    file_data_map: std.AutoHashMap(usize, []const u8),
    serial_number_counter: u16,
    allocator: std.mem.Allocator,

    /// Creates a new FileSystemTree (owned by the caller) and initializes it with the
    /// root directory. The root directory is owned by the FileSystemTree and will
    /// deallocate it with .destroy().
    pub fn create(allocator: std.mem.Allocator) !*FileSystemTree {
        var this: *FileSystemTree = try allocator.create(FileSystemTree);
        errdefer allocator.destroy(this);

        this.* = .{
            .allocator = allocator,
            .file_data_map = std.AutoHashMap(usize, []const u8).init(allocator),
            .serial_number_counter = 1,
            .root = try INode.create(
                this.allocator,
                "/",
                this.getSerialNum(),
                0,
                Timestamp.currentTime(),
                0o755,
                null,
                null,
                null,
            ),
        };

        // create base directories
        try this.root.addChildINode(try INode.create(this.allocator, "tmp", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        try this.root.addChildINode(try INode.create(this.allocator, "home", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        try this.root.addChildINode(try INode.create(this.allocator, "bin", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        try this.root.addChildINode(try INode.create(this.allocator, "dev", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        return this;
    }

    /// @returns serial number pre-incremented
    fn getSerialNum(self: *FileSystemTree) u64 {
        defer self.serial_number_counter += 1;
        return self.serial_number_counter;
    }

    /// @param file_path: string full path to file
    /// @param flags: int W_Flags
    /// @param data: string data to write
    /// @returns number of bytes written
    /// @returns -1 if file already exists and W_Flags.EXCL is set
    /// @returns -2 if file_path is not found
    pub fn write(
        self: *FileSystemTree,
        file_path: []const u8,
        flags: u32,
        data: []const u8,
    ) !usize {
        //check if file exists
        var file = self.getINode(file_path) catch null;

        // if file already exists and W_Flags.EXCL, error out
        if (flags & @intFromEnum(W_Flags.EXCL) != 0 and file != null) {
            return FileOpenError.AccessDenied;
        }

        // create file if it doesn't exist and W_Flags.CREAT is set
        if (flags & @intFromEnum(W_Flags.CREAT) != 0 and file == null) {
            const dir = try self.getINode(file_path[0..std.mem.lastIndexOf(u8, file_path, "/").?]);

            file = try INode.create(
                self.allocator,
                file_path[std.mem.lastIndexOf(u8, file_path, "/").? + 1 ..],
                self.getSerialNum(),
                data.len,
                Timestamp.currentTime(),
                0o755,
                null,
                null,
                null,
            );
            // create file
            try dir.addChildINode(file.?);
        }

        if (file == null) {
            return FileOpenError.FileNotFound;
        }

        const found_file = file.?;

        // write data to file
        if (flags & @intFromEnum(W_Flags.APPEND) != 0) {
            const old_data = self.file_data_map.get(found_file.serial_number);
            if (old_data) |old| {
                var buf = self.allocator.alloc(u8, old.len + data.len + 1) catch unreachable;
                std.mem.copyForwards(u8, buf, old);
                std.mem.copyForwards(u8, buf[old.len..], data);
                buf[data.len + old.len] = 0;
                try self.file_data_map.put(found_file.serial_number, buf);
            } else {
                const buf = self.allocator.dupe(u8, data) catch unreachable;
                try self.file_data_map.put(found_file.serial_number, buf);
            }
        } else if (flags & @intFromEnum(W_Flags.TRUNC) != 0) {
            const buf = self.allocator.dupe(u8, data) catch unreachable;
            try self.file_data_map.put(found_file.serial_number, buf);
        }

        return data.len;
    }

    /// @param file_path: string full path to file
    /// @returns string data read from file
    pub fn read(self: *FileSystemTree, file_path: []const u8) FileOpenError![]const u8 {
        const file = try self.getINode(file_path);
        return self.file_data_map.get(file.serial_number) orelse "FAIL";
    }

    /// @return returns the INode of the file located at file_path
    /// @param file_path: string
    pub fn getINode(self: *FileSystemTree, file_path: []const u8) FileOpenError!*INode {
        var current_node = self.root;
        var input_path_itr = std.mem.splitScalar(u8, file_path, '/');
        _ = input_path_itr.first(); // skip first element

        // iterate through input path
        while (input_path_itr.next()) |next_node_name| {

            // get next node or error if not found
            const next_node: *INode = for (current_node.children.items) |child_node| {
                if (std.mem.eql(u8, child_node.name, next_node_name)) {
                    break child_node;
                }
            } else return FileOpenError.FileNotFound;

            current_node = next_node;
        }
        return current_node;
    }

    /// deallocates memory the entire inode tree
    pub fn destroy(self: *FileSystemTree) void {
        var value_iter = self.file_data_map.valueIterator();
        while (value_iter.next()) |value| {
            self.allocator.free(value.*);
        }
        self.file_data_map.deinit();
        self.root.deallocate(self.allocator);
        self.allocator.destroy(self);
    }
};
const W_Flags = enum {
    APPEND,
    CREAT,
    EXCL,
    TRUNC,
};

test "init" {
    const allocator = std.testing.allocator;
    const fs = try FileSystemTree.create(allocator);
    defer fs.destroy();
}

test "write only" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    const bytes_written = try fs.write("/tmp/test.txt", @intFromEnum(W_Flags.CREAT), "Hello There");
    try std.testing.expect(bytes_written == 11);
}

test "read and write" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);

    defer fs.destroy();

    const bytes_written = try fs.write("/tmp/test.txt", @intFromEnum(W_Flags.CREAT), "Hello There");
    const bytes_read = try fs.read("/tmp/test.txt");

    try std.testing.expect(bytes_written == 11);
    try std.testing.expect(std.mem.eql(u8, bytes_read, "Hello There"));
}

test "fuzz read and write" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            const allocator = std.testing.allocator;
            var fs = try FileSystemTree.create(allocator);
            defer fs.destroy();

            _ = try fs.write("/tmp/test.txt", @intFromEnum(W_Flags.CREAT), input);
            const bytes_read = try fs.read("/tmp/test.txt");
            try std.testing.expect(std.mem.eql(u8, bytes_read, input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

test "read non-existent file" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    try std.testing.expectError(FileOpenError.FileNotFound, fs.read("/tmp/test.txt"));
}
