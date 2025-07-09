const std = @import("std");

pub const Timestamp = struct {
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

pub const INode = struct {
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
        const this = try allocator.create(INode);
        errdefer allocator.destroy(this);

        this.* = .{
            .name = name,
            .serial_number = serial_number,
            .file_mode = file_mode,
            .owner = owner,
            .timestamp = timestamp,
            .size = size orelse 0,
            .children = children orelse std.ArrayList(*INode).init(allocator),
            .parents = parents orelse std.ArrayList(*INode).init(allocator),
        };
        return this;
    }

    // add a child INode to this INode
    // Ownership of input INode is transferred to this INode
    pub fn addChildINode(self: *INode, child: *INode) !void {
        try self.children.append(child);
        try child.parents.append(self);
    }

    // add a parent INode to this INode
    // Ownership of this INode is transferred to input INode
    pub fn addParentINode(self: *INode, parent: *INode) !void {
        try parent.children.append(self);
        try self.parents.append(parent);
    }

    // add a list of children INodes to this INode
    pub fn addChildArrayList(self: *INode, new_children: *std.ArrayList(*INode)) !void {
        try self.children.appendSlice(try new_children.toOwnedSlice());
    }

    // add a list of parents INodes to this INode
    pub fn AddParentArrayList(self: *INode, new_parents: *std.ArrayList(*INode)) !void {
        try self.parents.appendSlice(try new_parents.toOwnedSlice());
    }

    pub fn isDirectory(self: *INode) bool {
        return self.children.length > 0;
    }

    pub fn deallocate(self: *INode, alloc: std.mem.Allocator) void {
        for (self.children.items) |child| {
            child.deallocate(alloc); // recursively destroy children
        }
        self.children.deinit();
        self.parents.deinit();
        alloc.destroy(self);
    }
};

test INode {
    const allocator = std.testing.allocator;
    const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
    defer inode.deallocate(allocator);
}

test "addChildINode" {
    const allocator = std.testing.allocator;

    const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
    defer inode.deallocate(allocator);

    // do NOT defer as ownership is transferred to parent INode
    const child = try INode.create(allocator, "child", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);

    try inode.addChildINode(child);
}

test "addParentINode" {
    const allocator = std.testing.allocator;

    // do NOT defer as ownership is transferred to parent INode
    const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);

    const parent = try INode.create(allocator, "parent", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
    defer parent.deallocate(allocator);

    try inode.addParentINode(parent);
}

// test "empty addChildArrayList" {
//     const allocator = std.testing.allocator;
//
//     const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
//     defer inode.deallocate(allocator);
//
//     try inode.addChildArrayList(&std.ArrayList(*INode).init(allocator));
// }
//
// test "empty addParentArrayList" {
//     const allocator = std.testing.allocator;
//
//     const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
//     defer inode.deallocate(allocator);
//
//     try inode.AddParentArrayList(&std.ArrayList(*INode).init(allocator));
// }

// test "addChildArrayList" {
//     const allocator = std.testing.allocator;
//
//     const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
//     defer inode.deallocate(allocator);
//
//     const child = try INode.create(allocator, "child", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
//     defer child.deallocate(allocator);
//
//     var arr = std.ArrayList(*INode).init(allocator);
//     defer arr.deinit();
//
//     try arr.append(child);
//
//     try inode.addChildArrayList(&arr);
// }
//
// test "addParentArrayList" {
//     const allocator = std.testing.allocator;
//
//     const inode = try INode.create(allocator, "test", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
//     defer inode.deallocate(allocator);
//
//     const parent = try INode.create(allocator, "parent", 1, 2, Timestamp.currentTime(), 0o755, null, null, null);
//     defer parent.deallocate(allocator);
//
//     var arr = std.ArrayList(*INode).init(allocator);
//     defer arr.deinit();
//
//     try arr.append(parent);
//
//     try inode.AddParentArrayList(&arr);
// }
//
