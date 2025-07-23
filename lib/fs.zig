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
    inodes_list: std.ArrayList(INode),
    root: usize,
    file_data_map: std.AutoHashMap(usize, []const u8),
    fd_table: std.AutoHashMap(usize, u64), // file descriptor -> serial number
    serial_number_counter: usize,
    allocator: std.mem.Allocator,

    pub const O_Flags = struct {
        CREAT: bool = false,
        EXCL: bool = false,
    };
    pub const W_Flags = packed struct {
        APPEND: bool = false,
        TRUNC: bool = false,
    };

    /// Creates a new FileSystemTree (owned by the caller) and initializes it with the
    /// root directory. The root directory is owned by the FileSystemTree and will
    /// deallocate it with .destroy().
    pub fn create(allocator: std.mem.Allocator) !*FileSystemTree {
        var this: *FileSystemTree = try allocator.create(FileSystemTree);
        errdefer allocator.destroy(this);

        this.* = .{
            .allocator = allocator,
            .file_data_map = std.AutoHashMap(usize, []const u8).init(allocator),
            .inodes_list = std.ArrayList(INode).init(allocator),
            .fd_table = std.AutoHashMap(usize, u64).init(allocator),
            .serial_number_counter = 0,
            .root = this.getSerialNum(),
        };

        try this.inodes_list.append(INode.create(.{
            .allocator = this.allocator,
            .name = "/",
            .serial_number = this.getSerialNum(),
            .file_type = FileType.directory,
        }));

        // fill fd_table with stdin, stdout, stderr
        // stdin, stdout, and stderr are floating INodes, only accessable by FD
        const outputs = [_][]const u8{ "stdin", "stdout", "stderr" };
        for (outputs, 0..) |output, i| {
            const node = INode.create(.{
                .allocator = this.allocator,
                .name = output,
                .serial_number = this.getSerialNum(),
                .file_type = FileType.character_device,
            });
            try this.inodes_list.append(node);
            try this.fd_table.put(i, node.serial_number);
        }

        // create base directories
        const children = [_][]const u8{ "tmp", "home", "bin", "dev" };
        for (children) |child| {
            const node = INode.create(.{
                .name = child,
                .serial_number = this.getSerialNum(),
                .file_type = FileType.directory,
                .parent = this.root,
                .allocator = this.allocator,
            });
            try this.inodes_list.append(node);
            try this.addChildINode(this.root, node.serial_number);
        }

        return this;
    }

    /// @param file_path: string full path to file
    /// @param flags: O_Flags
    /// @returns file descriptor
    pub fn open(self: *FileSystemTree, file_path: []const u8, flags: O_Flags) !isize {
        // find next open FD
        const next_fd = for (0..std.math.maxInt(isize)) |idx| {
            if (!self.fd_table.contains(idx)) {
                break idx;
            }
        };

        // if file already exists, modify fd_table and return fd
        const node = self.getINode(file_path) catch null;
        if (node) |n| {
            if (flags.EXCL == true) {
                return FileOpenError.Exist;
            }
            try self.fd_table.put(next_fd, n.serial_number);
            return next_fd;
        }

        if (flags.CREAT == false) {
            return FileOpenError;
        }

        self.touch(file_path);

        return next_fd;
    }

    /// @param fd: file descriptor to close
    /// @throws FileDescriptorError.BADFD if fd is not found in fd_table
    pub fn close(self: *FileSystemTree, fd: usize) !void {
        if (self.fd_table.remove(fd)) {
            return;
        } else {
            return error.FileDescriptorError.BADFD;
        }
    }

    /// @param fd: file descriptor to read from
    /// @returns string data read from file
    /// @throws FileDescriptorError.BADFD if fd is not found in fd_table
    pub fn read(self: *FileSystemTree, fd: usize) FileOpenError![]const u8 {
        const serial = self.fd_table.get(fd) orelse return error.FileDescriptorError.BADFD;
        return self.file_data_map.get(serial) orelse unreachable;
    }

    /// @param fd: file descriptor to write to
    /// @param flags: W_Flags
    /// @param data: string data to write
    /// @returns number of bytes written
    /// @throws FileDescriptorError.BADFD if fd is not found in fd_table
    pub fn write(self: *FileSystemTree, fd: usize, flags: W_Flags, data: []const u8) !usize {
        const serial = self.fd_table.get(fd) orelse return error.FileDescriptorError.BADFD;

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
    fn getINode(self: *FileSystemTree, file_path: []const u8) FileOpenError!*INode {
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
        for (self.inodes_list.items) |inode| {
            inode.children.deinit();
        }
        self.file_data_map.deinit();
        self.allocator.destroy(self);
    }

    // ---------- INode Functions ----------

    fn get(self: *FileSystemTree, serial_number: usize) *INode {
        if (serial_number > self.inodes_list.items.len) {
            std.debug.panic("FileSystemTree.get() failed, serial_number > inodes_list.items.len ({d} > {d})\n", .{ serial_number, self.inodes_list.items.len });
        }
        return &self.inodes_list.items[serial_number];
    }

    /// @brief Add a child INode to this INode and update input INode. Ownership of input INode is transferred to this INode
    /// @param child: INode to add to this INode's children and to be owned by this INode
    pub fn addChildINode(self: *FileSystemTree, parent: usize, child: usize) !void {
        try self.get(parent).children.append(child);
        self.get(child).parent = parent;
    }

    /// @brief Add a list of children INodes to this INode
    /// @param new_children: ArrayList of INodes to add to this INode's children
    pub fn addChildArrayList(self: *FileSystemTree, parent: usize, new_children: *std.ArrayList(usize)) !void {
        const child_slice = try new_children.toOwnedSlice();
        try self.get(parent).children.appendSlice(child_slice);
        for (child_slice) |child| {
            self.get(child).parent = parent;
        }
    }

    // ---------- Private Functions ----------

    /// @brief Creates a file with the given path and data type
    /// @param file_path: string full path to file
    /// @param data_type: null or FileType
    /// @returns void
    fn touch(
        self: *FileSystemTree,
        file_path: []const u8,
        data_type: ?FileType,
    ) !void {
        const parent_directory = try self.getINode(file_path[0..std.mem.lastIndexOf(u8, file_path, "/").?]);

        const file = try INode.create(.{
            .allocator = self.allocator,
            .name = file_path[std.mem.lastIndexOf(u8, file_path, "/").? + 1 ..],
            .serial_number = self.getSerialNum(),
            .data_type = data_type orelse FileType.binary,
            .timestamp = Timestamp.currentTime(),
            .parent = parent_directory,
        });
        try parent_directory.addChildINode(file.?);
    }

    /// @returns serial number pre-incremented
    fn getSerialNum(self: *FileSystemTree) usize {
        if (self.serial_number_counter != self.inodes_list.items.len) {
            std.debug.panic("Invariant violated, serial_number_counter != inodes_list.items.len ({d} != {d})\n", .{ self.serial_number_counter, self.inodes_list.items.len });
        }
        defer self.serial_number_counter += 1;
        return self.serial_number_counter;
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

    const bytes_written = try fs.writeByPath("/tmp/test.txt", .{ .CREAT = true }, "Hello There", .string);
    try std.testing.expect(bytes_written == 11);
}

test "read and write only" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);

    defer fs.destroy();

    const bytes_written = try fs.writeByPath("/tmp/test.txt", .{ .CREAT = true }, "Hello There", .string);
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

            _ = try fs.writeByPath("/tmp/test.txt", .{ .CREAT = true }, input, .string);
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

test "write to already existing file with EXCL flag" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();
    _ = try fs.writeByPath("/tmp/test.txt", .{ .CREAT = true }, "Hello There", .string);
    try std.testing.expectError(FileOpenError.AccessDenied, fs.writeByPath("/tmp/test.txt", .{ .EXCL = true }, "Hello There", .string));
}

// INode tests

// test "addChildINode" {
//     const allocator = std.testing.allocator;
//
//     const inode = try INode.create(.{
//         .allocator = allocator,
//         .name = "test",
//         .serial_number = 1,
//         .file_type = FileType.directory,
//         .timestamp = Timestamp.currentTime(),
//     });
//
//     // do NOT defer as ownership is transferred to parent INode
//     const child = try INode.create(.{
//         .allocator = allocator,
//         .name = "child",
//         .serial_number = 2,
//         .file_type = FileType.directory,
//         .timestamp = Timestamp.currentTime(),
//     });
//
//     try inode.addChildINode(child);
// }
//
// test "changeParent" {
//     const allocator = std.testing.allocator;
//
//     // do NOT defer as ownership is transferred to parent INode
//     const inode = try INode.create(.{
//         .allocator = allocator,
//         .name = "test",
//         .serial_number = 1,
//         .file_type = FileType.directory,
//         .timestamp = Timestamp.currentTime(),
//     });
//
//     const parent = try INode.create(.{
//         .allocator = allocator,
//         .name = "parent",
//         .serial_number = 1,
//         .file_type = FileType.directory,
//         .timestamp = Timestamp.currentTime(),
//     });
//
//     try inode.changeParent(parent);
// }
