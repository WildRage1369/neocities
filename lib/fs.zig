const std = @import("std");
const builtin = @import("builtin");

const INode = @import("INode.zig").INode;
const Timestamp = @import("INode.zig").Timestamp;
const FileType = @import("INode.zig").FileType;

/// FileSystemTree is a file system implementation that uses a hash table to store
/// file data. It is designed to be used in a WebAssembly environment.
/// It is required to call .destroy() on it to free the memory
pub const FileSystemTree = struct {
    _inode_list: std.ArrayListUnmanaged(INode),
    _root: usize,
    _data_map: std.AutoHashMapUnmanaged(usize, []u8),
    _fd_table: std.AutoHashMapUnmanaged(usize, usize), // file descriptor -> serial number
    _serial_number_counter: usize,
    _alloc: std.mem.Allocator,

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
        var self: *FileSystemTree = try allocator.create(FileSystemTree);
        errdefer allocator.destroy(self);

        self.* = .{
            ._alloc = allocator,
            ._data_map = std.AutoHashMapUnmanaged(usize, []u8){},
            ._inode_list = std.ArrayListUnmanaged(INode){},
            ._fd_table = std.AutoHashMapUnmanaged(usize, usize){},
            ._serial_number_counter = 0,
            ._root = self.getSerialNum(),
        };

        try self._inode_list.append(self._alloc, INode.create(.{
            .name = "/",
            .serial_number = self._root,
            .file_type = FileType.directory,
        }));

        // fill fd_table with stdin, stdout, stderr
        // stdin, stdout, and stderr are floating INodes, only accessable by FD
        const outputs = [_][]const u8{ "stdin", "stdout", "stderr" };
        for (outputs, 0..) |output, i| {
            const node = INode.create(.{
                .name = output,
                .serial_number = self.getSerialNum(),
                .file_type = FileType.character_device,
            });
            try self._inode_list.append(self._alloc, node);
            try self._fd_table.put(self._alloc, i, node.serial_number);
        }

        // create base directories
        const children = [_][]const u8{ "tmp", "home", "bin", "dev" };
        for (children) |child| {
            const node = INode.create(.{
                .name = child,
                .serial_number = self.getSerialNum(),
                .file_type = FileType.directory,
                .parent = self._root,
            });
            try self._inode_list.append(self._alloc, node);
            try self.addChildINode(self._root, node.serial_number);
        }

        return self;
    }

    /// Returns a fild descriptor pointing to the file located at file_path.
    ///
    /// O_Flags.CREAT: creates the file if it doesnt exist and is ignored
    /// if the file already exists.
    /// O_Flags.EXCL: will cause the function to fail if the file already
    /// exists and is ignored if the file does not exist.
    pub fn open(self: *FileSystemTree, file_path: []const u8, flags: O_Flags) !usize {
        // find next open FD
        const next_fd = for (0..std.math.maxInt(isize)) |idx| {
            if (!self._fd_table.contains(idx)) {
                break idx;
            }
        } else std.debug.panic("FileSystemTree.open() failed, no open FDs available\n", .{});

        const node = self.getByPath(file_path) catch null;

        if (node == null and flags.CREAT == false) {
            return error.FileNotFound;
        } else if (node != null and flags.EXCL == true) {
            return error.FileExists;
        }

        // get serial number of file or create file
        const serial = if (node) |n| n.serial_number else try self.touch(file_path);
        try self._fd_table.put(self._alloc, next_fd, serial);

        return next_fd;
    }

    /// Closes the file descriptor and removes it from the fd_table.
    /// Does nothing if the file descriptor is not found in the fd_table.
    pub fn close(self: *FileSystemTree, fd: usize) void {
        _ = self._fd_table.remove(fd);
    }

    /// Reads the file located at the file descriptor and returns the data.
    /// Returns error.BADFD if the file descriptor is not found in the fd_table.
    pub fn read(self: *FileSystemTree, fd: usize) ![] u8 {
        const serial = self._fd_table.get(fd) orelse return error.BADFD;
        return self._data_map.get(serial) orelse unreachable;
    }

    /// Writes the data to the file located at the file descriptor.
    /// Returns error.BADFD if the file descriptor is not found in the fd_table.
    ///
    /// W_Flags.TRUNC will truncate the file to 0 bytes and then write the data.
    /// W_Flags.APPEND will append the data to the end of the file.
    pub fn write(self: *FileSystemTree, fd: usize, flags: W_Flags, data: []const u8) !usize {
        const serial = self._fd_table.get(fd) orelse return error.BADFD;

        if (flags.TRUNC == true or flags.APPEND == false) {
            const buf = self._alloc.dupe(u8, data) catch unreachable;
            try self._data_map.put(self._alloc, serial, buf);
        } else if (flags.APPEND == true) {
            const old_data = self._data_map.get(serial);
            if (old_data) |old| {
                var buf = self._alloc.alloc(u8, old.len + data.len + 1) catch unreachable;
                std.mem.copyForwards(u8, buf, old);
                std.mem.copyForwards(u8, buf[old.len..], data);
                buf[data.len + old.len] = 0;
                try self._data_map.put(self._alloc, serial, buf);
            } else {
                const buf = self._alloc.dupe(u8, data) catch unreachable;
                try self._data_map.put(self._alloc, serial, buf);
            }
        } else {
            return 0;
        }
        return data.len;
    }

    /// deallocates memory the entire inode tree
    pub fn destroy(self: *FileSystemTree) void {
        var value_iter = self._data_map.valueIterator();
        while (value_iter.next()) |value| {
            self._alloc.free(value.*);
        }
        for (self._inode_list.items) |*inode| {
            inode.children.deinit(self._alloc);
        }
        self._inode_list.deinit(self._alloc);
        self._fd_table.deinit(self._alloc);
        self._data_map.deinit(self._alloc);
        self._alloc.destroy(self);
    }

    // ---------- INode Functions ----------

    /// @brief Add a child INode to this INode and update input INode. Ownership of input INode is transferred to this INode
    /// @param child: INode to add to this INode's children and to be owned by this INode
    pub fn addChildINode(self: *FileSystemTree, parent: usize, child: usize) !void {
        try self.getBySerial(parent).children.append(self._alloc, child);
        self.getBySerial(child).parent = parent;
    }

    /// @brief Add a list of children INodes to this INode
    /// @param new_children: ArrayList of INodes to add to this INode's children
    pub fn addChildArrayList(self: *FileSystemTree, parent: usize, new_children: *std.ArrayList(usize)) !void {
        const child_slice = try new_children.toOwnedSlice();
        try self.getBySerial(parent).children.appendSlice(child_slice);
        for (child_slice) |child| {
            self.getBySerial(child).parent = parent;
        }
    }

    // ---------- Private Functions ----------

    /// Creates a file at the given path
    /// Returns the serial number of the file.
    fn touch(
        self: *FileSystemTree,
        file_path: []const u8,
    ) !usize {
        const parent_directory = try self.getByPath(file_path[0..std.mem.lastIndexOf(u8, file_path, "/").?]);

        const file = INode.create(.{
            .name = file_path[std.mem.lastIndexOf(u8, file_path, "/").? + 1 ..],
            .file_type = .string,
            .serial_number = self.getSerialNum(),
            .timestamp = Timestamp.currentTime(),
            .parent = parent_directory.serial_number,
        });
        try self._inode_list.append(self._alloc, file);
        try self.addChildINode(parent_directory.serial_number, file.serial_number);
        return file.serial_number;
    }

    /// Returns a pointer to the INode with the given serial number.
    /// Panics if serial_number is greater than the number of INodes in the list.
    fn getBySerial(self: *FileSystemTree, serial_number: usize) *INode {
        if (serial_number > self._inode_list.items.len) {
            std.debug.panic("FileSystemTree.get() failed, serial_number > inodes_list.items.len ({d} > {d})\n", .{ serial_number, self._inode_list.items.len });
        }
        return &self._inode_list.items[serial_number];
    }

    /// Returns a pointer to the INode of the file located at file_path.
    /// Returns error.FileNotFound if the file does not exist.
    fn getByPath(self: *FileSystemTree, file_path: []const u8) !*INode {
        var current_node = self._root;
        var input_path_itr = std.mem.splitScalar(u8, file_path, '/');
        _ = input_path_itr.first(); // skip first element

        // iterate through input path
        while (input_path_itr.next()) |next_node_name| {

            // get next node or error if not found
            const next_node: usize = for (self.getBySerial(current_node).children.items) |child_node| {
                if (std.mem.eql(u8, self.getBySerial(child_node).name, next_node_name)) {
                    break child_node;
                }
            } else return error.FileNotFound;

            current_node = next_node;
        }
        return self.getBySerial(current_node);
    }

    /// Returns serial number pre-incremented
    /// Asserts invariant: serial_number_counter == number of INodes in the list.
    fn getSerialNum(self: *FileSystemTree) usize {
        if (self._serial_number_counter != self._inode_list.items.len) {
            std.debug.panic("Invariant violated, serial_number_counter != inodes_list.items.len ({d} != {d})\n", .{ self._serial_number_counter, self._inode_list.items.len });
        }
        defer self._serial_number_counter += 1;
        return self._serial_number_counter;
    }

    // ---------- Print Debug Functions ---------

    /// Prints the contents of the fd_table in the format "fd: serial_number"
    fn printFDTable(self: *FileSystemTree) void {
        var it = self._fd_table.iterator();
        while (it.next()) |entry| {
            std.debug.print("fd: {d}, serial_number: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
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

    const bytes_written = try fs.write(fd, .{}, "Hello There");
    const bytes_read = try fs.read(fd);

    try std.testing.expectEqual(bytes_written, 11);
    try std.testing.expectEqualStrings("Hello There", bytes_read);
}

test "fuzz read and write" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            const allocator = std.testing.allocator;
            var fs = try FileSystemTree.create(allocator);
            defer fs.destroy();

            const fd = try fs.open("/tmp/test.txt", .{ .CREAT = true });
            defer fs.close(fd);

            _ = try fs.write(fd, .{}, input);
            const bytes_read = try fs.read(fd);

            try std.testing.expect(std.mem.eql(u8, bytes_read, input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

test "open non-existent file without .CREAT flag" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    const err = fs.open("/tmp/test.txt", .{});
    try std.testing.expectError(error.FileNotFound, err);
}

test "open already existing file with EXCL flag" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();

    const fd = try fs.open("/tmp/test.txt", .{ .CREAT = true });
    defer fs.close(fd);

    const err = fs.open("/tmp/test.txt", .{ .EXCL = true, .CREAT = true });
    try std.testing.expectError(error.FileExists, err);
}
