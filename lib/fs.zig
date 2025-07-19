const std = @import("std");
const builtin = @import("builtin");

const INode = @import("INode.zig").INode;
const Timestamp = @import("INode.zig").Timestamp;
const FileType = @import("INode.zig").FileType;

const FileOpenError = error{
    Exist,
    AccessDenied,
    FileNotFound,
};

/// FileSystemTree is a file system implementation that uses a hash table to store
/// file data. It is designed to be used in a WebAssembly environment.
/// It is required to call .destroy() on it to free the memory
pub const FileSystemTree = struct {
    root: *INode,
    file_data_map: std.AutoHashMap(usize, []const u8),
    fd_table: std.AutoHashMap(usize, u64), // file descriptor -> serial number
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
            .fd_table = std.AutoHashMap(usize, u64).init(allocator),
            .serial_number_counter = 0,
            .root = try INode.create(.{
                .allocator = this.allocator,
                .name = "/",
                .serial_number = this.getSerialNum(),
                .file_type = FileType.directory,
            }),
        };

        // create base directories
        var opts: INode.CreateArgs = .{
            .name = "tmp",
            .serial_number = this.getSerialNum(),
            .file_type = FileType.directory,
            .parent = this.root,
            .allocator = this.allocator,
        };

        _ = try INode.create(opts);
        opts.name = "home";
        opts.serial_number = this.getSerialNum();
        _ = try INode.create(opts);
        opts.name = "bin";
        opts.serial_number = this.getSerialNum();
        _ = try INode.create(opts);
        opts.name = "dev";
        opts.serial_number = this.getSerialNum();
        _ = try INode.create(opts);

        // fill fd_table with stdin, stdout, stderr
        // stdin, stdout, and stderr are floating INodes, only accessable by FD
        const stdin = try INode.create(.{
            .allocator = this.allocator,
            .name = "stdin",
            .serial_number = this.getSerialNum(),
            .file_type = FileType.character_device,
            .parent = try this.getINode("/dev"),
        });
        try this.fd_table.put(0, stdin.serial_number);

        const stdout = try INode.create(.{
            .allocator = this.allocator,
            .name = "stdout",
            .serial_number = this.getSerialNum(),
            .file_type = FileType.character_device,
            .parent = try this.getINode("/dev"),
        });
        try this.fd_table.put(1, stdout.serial_number);

        const stderr = try INode.create(.{
            .allocator = this.allocator,
            .name = "stderr",
            .serial_number = this.getSerialNum(),
            .file_type = FileType.character_device,
            .parent = try this.getINode("/dev"),
        });
        try this.fd_table.put(2, stderr.serial_number);

        return this;
    }

    pub const O_Flags = struct {
        CREAT: bool = false,
        EXCL: bool = false,
    };


    /// @param file_path: string full path to file
    /// @param flags: O_Flags
    /// @returns file descriptor
    pub fn open(self: *FileSystemTree, file_path: []const u8, flags: O_Flags) !usize {
        // find next open FD
        const next_fd = for (0..std.math.maxInt(isize)) |idx| {
            if (!self.fd_table.contains(idx)) {
                break idx;
            }
        } else unreachable;

        // if file already exists, modify fd_table and return fd
        var node = self.getINode(file_path) catch null;
        if (node != null) {
            if (flags.EXCL == true) {
                return FileOpenError.Exist;
            }
        } else {
            if (flags.CREAT == false) {
                return error.BAD;
            }

            try self.touch(file_path);
            node = self.getINode(file_path) catch std.debug.panic("self.touch() failed at {any}", .{@src()});
        }

        try self.fd_table.put(next_fd, node.?.serial_number);

        return next_fd;
    }

    /// @param fd: file descriptor to close
    pub fn close(self: *FileSystemTree, fd: usize) void {
        if (self.fd_table.remove(fd)) {
            return;
        }
    }

    /// @param fd: file descriptor to read from
    /// @returns string data read from file
    /// @throws FileDescriptorError.BADFD if fd is not found in fd_table
    pub fn read(self: *FileSystemTree, fd: usize) ![]const u8 {
        const serial = self.fd_table.get(fd) orelse return error.BADFD;
        return self.file_data_map.get(serial) orelse unreachable;
    }

    pub const W_Flags = packed struct {
        APPEND: bool = false,
        TRUNC: bool = false,
    };

    /// @param fd: file descriptor to write to
    /// @param flags: W_Flags
    /// @param data: string data to write
    /// @returns number of bytes written
    /// @throws FileDescriptorError.BADFD if fd is not found in fd_table
    pub fn write(self: *FileSystemTree, fd: usize, flags: W_Flags, data: []const u8) !usize {
        const serial = self.fd_table.get(fd) orelse return error.BADFD;

        if (flags.TRUNC == true or flags.APPEND == false) {
            const buf = self.allocator.dupe(u8, data) catch unreachable;
            try self.file_data_map.put(serial, buf);
        } else if (flags.APPEND == true) {
            const old_data = self.file_data_map.get(serial);
            if (old_data) |old| {
                var buf = self.allocator.alloc(u8, old.len + data.len + 1) catch unreachable;
                std.mem.copyForwards(u8, buf, old);
                std.mem.copyForwards(u8, buf[old.len..], data);
                buf[data.len + old.len] = 0;
                try self.file_data_map.put(serial, buf);
            } else {
                const buf = self.allocator.dupe(u8, data) catch unreachable;
                try self.file_data_map.put(serial, buf);
            }
        } else {
            return 0;
        }
        return data.len;
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
        self.fd_table.deinit();
        self.file_data_map.deinit();
        self.root.deallocate(self.allocator);
        self.allocator.destroy(self);
    }

    // ---------- Private Functions ----------

    /// @brief Creates a file with the given path and data type
    /// @param file_path: string full path to file
    /// @param data_type: null or FileType
    /// @returns void
    fn touch(
        self: *FileSystemTree,
        file_path: []const u8,
    ) !void {
        const parent_directory = try self.getINode(file_path[0..std.mem.lastIndexOf(u8, file_path, "/").?]);

        const file = try INode.create(.{
            .allocator = self.allocator,
            .name = file_path[std.mem.lastIndexOf(u8, file_path, "/").? + 1 ..],
            .serial_number = self.getSerialNum(),
            .timestamp = Timestamp.currentTime(),
            .parent = parent_directory,
            .file_type = FileType.binary,
        });
        try self.file_data_map.put(file.serial_number, "");
    }

    /// @returns serial number pre-incremented
    fn getSerialNum(self: *FileSystemTree) u64 {
        defer self.serial_number_counter += 1;
        return self.serial_number_counter;
    }

    // ---------- Debug (printing) Functions ----------

    fn printFDTable(self: *FileSystemTree) void {
        for (self.fd_table.keys()) |fd| {
            std.debug.print("fd: {d}, serial: {d}\n", .{ fd, self.fd_table.get(fd).? });
        }
    }

    fn printTree(self: *FileSystemTree) void {
        printNode(self, self.root, 0);
    }

    fn printNode(self: *FileSystemTree, node: *INode, depth: u32) void {
        const data = self.file_data_map.get(node.serial_number) orelse "";
        for (0..depth) |_| {
            std.debug.print("\t", .{});
        }
        std.debug.print("{s} ({d}): '{s}'\n", .{ node.name, node.serial_number, data });
        if (node.children.items.len == 0) {
            return;
        }
        for (node.children.items) |child| {
            printNode(self, child, depth + 1);
        }
    }
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

    const fd = try fs.open("/tmp/test.txt", .{ .CREAT = true });
    defer fs.close(fd);

    const bytes_written = try fs.write(fd, .{}, "Hello There");
    try std.testing.expect(bytes_written == 11);
}

test "read and write" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    const fd = try fs.open("/tmp/test.txt", .{ .CREAT = true });
    defer fs.close(fd);

    const num_bytes_written = try fs.write(fd, .{}, "Hello There");
    const file_data_read = try fs.read(fd);

    try std.testing.expect(num_bytes_written == 11);
    try std.testing.expect(std.mem.eql(u8, file_data_read, "Hello There"));
}

test "read non-existent file" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    try std.testing.expectError(error.BADFD, fs.read(4));
}

test "open create already existing file with EXCL flag" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    _ = try fs.open("/tmp/test.txt", .{ .CREAT = true });
    try std.testing.expectError(error.Exist, fs.open("/tmp/test.txt", .{ .CREAT = true, .EXCL = true }));
}
