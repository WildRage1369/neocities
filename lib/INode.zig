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

pub const FileType = enum {
    directory,
    string,
    binary,
    character_device,
};

pub const INode = struct {
    file_type: FileType,
    serial_number: usize,
    name: []const u8,
    file_mode: u16, // file permissions
    owner: usize, // user id
    timestamp: Timestamp, // Timestamp object with ctime, mtime, atime
    size: u64,
    children: std.ArrayListUnmanaged(usize),
    parent: usize,

    pub fn create(options: INode.CreateArgs) INode {
        return .{
            .name = options.name,
            .file_type = options.file_type,
            .serial_number = options.serial_number,
            .file_mode = options.file_mode,
            .owner = options.owner,
            .timestamp = options.timestamp orelse Timestamp.currentTime(),
            .size = options.size orelse 0,
            .children = options.children orelse std.ArrayListUnmanaged(usize){},
            .parent = options.parent orelse options.serial_number,
        };
    }

    pub const CreateArgs = struct {
        name: []const u8,
        serial_number: usize,
        file_type: FileType = .binary,
        timestamp: ?Timestamp = null,
        owner: usize = 1,
        file_mode: u16 = 0o755,
        size: ?u64 = null,
        children: ?std.ArrayListUnmanaged(usize) = null,
        parent: ?usize = null,
    };
};

test INode {
    _ = INode.create(.{
        .name = "test",
        .serial_number = 1,
    });
}
