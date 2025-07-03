const std = @import("std");
const builtin = @import("builtin");

extern fn logNum(data: u32) void;
extern fn logStr(ptr: [*:0]const u8) void;
extern fn logErr(ptr: [*:0]const u8) void;

fn panic(msg: []const u8, src: std.builtin.SourceLocation) noreturn {
    const string: [*:0]u8 = alloc.dupeZ(u8, msg) catch unreachable;

    logErr(string);
    var buf: [1024:0]u8 = undefined;
    var inx: usize = 0;
    std.mem.copyForwards(u8, buf[inx..], " at ");
    inx += 4;
    buf[inx + 1] = 0;
    const strings: [*:0]u8 = alloc.dupeZ(u8, buf[inx..]) catch unreachable;
    logErr(strings);
    std.mem.copyForwards(u8, buf[inx..], src.file);
    inx += src.file.len;
    std.mem.copyForwards(u8, buf[inx..], ":");
    inx += 1;

    var s = std.fmt.bufPrint(buf[inx..], "{}", .{src.line}) catch "";
    std.mem.copyForwards(u8, buf[inx..], s);
    inx += s.len;

    s = std.fmt.bufPrint(buf[inx..], "{}", .{src.column}) catch "";
    std.mem.copyForwards(u8, buf[inx..], s);
    inx += s.len;

    std.mem.copyForwards(u8, buf[inx..], src.fn_name);
    inx += src.fn_name.len;
    @trap();
}

const FileOpenError = error{
    AccessDenied,
    FileNotFound,
};

const alloc = if (builtin.target.cpu.arch == .wasm32) std.heap.wasm_allocator else std.testing.allocator;

var filesys: *FileSystemTree = undefined;

// start wasm string functions

// EXTERNAL: allocates memory for a string
export fn allocString(len: usize) [*]u8 {
    const arr = alloc.alloc(u8, len + 1) catch panic("allocString() failed", @src());
    logStr("allocString() done".ptr);
    return arr.ptr;
}

// INTERNAL: converts a wasm string pointer to a Zig string
fn readString(ptr: [*:0]u8) []const u8 {
    const str: []const u8 = std.mem.span(ptr);
    defer alloc.free(str);
    return str;
}

// start OS functions

// EXTERNAL: initializes the file system
export fn init() void {
    filesys = FileSystemTree.create(alloc) catch panic("FileSystemTree.create() failed", @src());
    logStr("init() done".ptr);
}

// EXTERNAL: opens a file and returns a serial number
export fn open(path_ptr: [*:0]u8) u64 {
    const path = readString(path_ptr);
    return (filesys.getINode(path) catch panic("FileSystemTree.getINode() failed", @src())).serial_number;
}

const INode = struct {
    serial_number: u64,
    name: []const u8,
    file_mode: u16, // file permissions
    owner: usize, // user id
    timestamp: Timestamp, // Timestamp object with ctime, mtime, atime
    size: u64,
    children: std.ArrayList(*INode),
    parents: std.ArrayList(*INode),

    pub fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
        serial_number: u64,
        owner: usize,
        timestamp: Timestamp,
        file_mode: u16,
        size: ?u64,
        children: ?std.ArrayList(*INode),
        parents: ?std.ArrayList(*INode),
    ) !*INode {
        var this = try allocator.create(INode);
        this.name = name;
        this.serial_number = serial_number;
        this.file_mode = file_mode;
        this.owner = owner;
        this.timestamp = timestamp;
        this.size = size orelse 0;
        this.children = children orelse std.ArrayList(*INode).init(allocator);
        this.parents = parents orelse std.ArrayList(*INode).init(allocator);
        return this;
    }

    // add a child INode to this INode
    pub fn addChildINode(self: *INode, child: *INode) !void {
        return try self.children.append(child);
    }

    // add a parent INode to this INode
    pub fn addParentINode(self: *INode, parent: *INode) !void {
        return try self.parents.append(parent);
    }

    // add a list of children INodes to this INode
    pub fn addChildSlice(self: *INode, new_children: std.ArrayList(*INode)) void {
        self.children.appendSlice(new_children.toOwnedSlice());
    }

    // add a list of parents INodes to this INode
    pub fn addParentSlice(self: *INode, new_parents: std.ArrayList(*INode)) void {
        self.parents.appendSlice(new_parents.toOwnedSlice());
    }

    pub fn isDirectory(self: *INode) bool {
        return self.children.length > 0;
    }

    pub fn destroy(self: *INode) void {
        for (self.children) |*child| {
            child.destroy();
        }
    }
};

const Timestamp = struct {
    ctime: i64 = 0,
    mtime: i64 = 0,
    atime: i64 = 0,

    pub fn currentTime() Timestamp {
        return Timestamp{
            .ctime = 0,
            .mtime = 0,
            .atime = 0,
        };
    }
};

/// FileSystemTree is a file system implementation that uses a hash table to store
/// file data. It is designed to be used in a WebAssembly environment.
/// It is required to call .destroy() on it to free the memory
const FileSystemTree = struct {
    root: *INode,
    file_data_map: std.AutoHashMap(usize, []const u8),
    serial_number_counter: u16 = 1,
    allocator: std.mem.Allocator,

    /// Creates a new FileSystemTree (owned by the caller) and initializes it with the
    /// root directory. The root directory is owned by the FileSystemTree and will 
    /// deallocate it with .destroy().
    pub fn create(allocator: std.mem.Allocator) !*FileSystemTree {
        var this: *FileSystemTree = try allocator.create(FileSystemTree);
        // create root node with rwxr-xr-x perms
        this.root = try INode.create(
            allocator,
            "/",
            this.getSerialNum(),
            0,
            Timestamp.currentTime(),
            0o755,
            null,
            null,
            null,
        );
        this.file_data_map = std.AutoHashMap(usize, []const u8).init(allocator);

        // create base directories
        try this.root.addChildINode(try INode.create(allocator, "tmp", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        try this.root.addChildINode(try INode.create(allocator, "home", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        try this.root.addChildINode(try INode.create(allocator, "bin", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
        try this.root.addChildINode(try INode.create(allocator, "dev", this.getSerialNum(), 0, Timestamp.currentTime(), 0o755, null, null, null));
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
        const file = self.getINode(file_path) catch null;

        // if file already exists and W_Flags.EXCL, error out
        if (flags & @intFromEnum(W_Flags.EXCL) != 0 and file != null) {
            return FileOpenError.AccessDenied;
        }

        // create file if it doesn't exist and W_Flags.CREAT is set
        if (flags & @intFromEnum(W_Flags.CREAT) != 0 and file == null) {
            const dir = try self.getINode(file_path[0..std.mem.lastIndexOf(u8, file_path, "/").?]);

            // create file
            try dir.addChildINode(
                try INode.create(
                    self.allocator,
                    file_path[std.mem.lastIndexOf(u8, file_path, "/").? + 1 ..],
                    self.getSerialNum(),
                    data.len,
                    Timestamp.currentTime(),
                    0o755,
                    null,
                    null,
                    null,
                ),
            );
        }

        if (file == null) {
            return FileOpenError.FileNotFound;
        }

        const found_file = file.?;

        // write data to file
        if (flags & @intFromEnum(W_Flags.APPEND) != 0) {
            const old_data = self.file_data_map.get(found_file.serial_number);
            if (old_data) |old| {
                var buf = self.allocator.alloc(u8, old.len + data.len) catch unreachable;
                std.mem.copyForwards(u8, buf, old);
                std.mem.copyForwards(u8, buf[old.len..], data);
                try self.file_data_map.put(found_file.serial_number, buf);
            } else {
                try self.file_data_map.put(found_file.serial_number, data);
            }
        } else if (flags & @intFromEnum(W_Flags.TRUNC) != 0) {
            try self.file_data_map.put(found_file.serial_number, data);
        }

        return data.len;
    }

    /// @param file_path: string full path to file
    /// @returns string data read from file
    pub fn read(self: *FileSystemTree, file_path: []const u8) FileOpenError!usize {
        const file = try self.getINode(file_path);
        return self.file_data_map.get(file.serial_number);
    }

    /// @return returns the INode of the file located at file_path
    /// @param file_path: string
    pub fn getINode(self: *FileSystemTree, file_path: []const u8) FileOpenError!*INode {
        var path_list = std.mem.splitScalar(u8, file_path, '/');
        var current = self.root;

        // iterate through input path
        dirs: while (path_list.next()) |node_name| {

            // search for subdirectory/file, return undefined if not found
            children: for (current.children.items) |child| {
                if (!std.mem.eql(u8, child.name, node_name)) {
                    continue :children;
                } // skip if name doesn't match

                current = child;
                continue :dirs;
            }
            return FileOpenError.FileNotFound;
        }
        return current;
    }

    /// deallocates memory the entire inode tree
    pub fn destroy(self: *FileSystemTree) void {
        self.root.destroy();
        self.file_data_map.deinit();
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
    defer allocator.destroy(fs);
}

test "write" {
    const allocator = std.testing.allocator;
    var fs = try FileSystemTree.create(allocator);
    defer fs.destroy();
    defer allocator.destroy(fs);
    const bytes_written = try fs.write("/tmp/test.txt", @intFromEnum(W_Flags.CREAT), "Hello There");
    try std.testing.expect(bytes_written == 12);
}
