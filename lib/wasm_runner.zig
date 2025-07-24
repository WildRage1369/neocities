const std = @import("std");
const builtin = @import("builtin");
const FileSystemTree = @import("fs.zig").FileSystemTree;

extern fn logNum(data: u32) void;
extern fn logStr(ptr: [*:0]const u8) void;
extern fn logErr(ptr: [*:0]const u8) void;

fn panic(msg: []const u8, src: std.builtin.SourceLocation) noreturn {
    const string: [*:0]u8 = wasm_alloc.dupeZ(u8, msg) catch unreachable;

    if (comptime builtin.target.cpu.arch == .wasm32) logErr(string);
    var buf: [1024:0]u8 = undefined;
    var inx: usize = 0;
    std.mem.copyForwards(u8, buf[inx..], " at ");
    inx += 4;
    buf[inx + 1] = 0;
    const strings: [*:0]u8 = wasm_alloc.dupeZ(u8, buf[inx..]) catch unreachable;
    if (comptime builtin.target.cpu.arch == .wasm32) logErr(strings);
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


const wasm_alloc = if (builtin.target.cpu.arch == .wasm32) std.heap.wasm_allocator else std.testing.allocator;

var filesys: *FileSystemTree = undefined;

// start wasm string functions

// INTERNAL: converts a wasm string pointer to a Zig string
fn readString(ptr: [*:0]u8) []const u8 {
    const str: []const u8 = std.mem.span(ptr);
    defer wasm_alloc.free(str);
    return str;
}

// EXTERNAL: allocates memory for a string
export fn allocString(len: usize) [*]u8 {
    const arr = wasm_alloc.alloc(u8, len + 1) catch panic("allocString() failed", @src());
    // if (comptime builtin.target.cpu.arch == .wasm32) logStr("allocString() done".ptr);
    return arr.ptr;
}

// EXTERNAL: initializes the file system
export fn init() void {
    filesys = FileSystemTree.create(wasm_alloc) catch panic("FileSystemTree.create() failed", @src());
    if (comptime builtin.target.cpu.arch == .wasm32) logStr("init() done".ptr);
}

// EXTERNAL: opens a file and returns a serial number
export fn open(path_ptr: [*:0]u8) u32 {
    const path = readString(path_ptr);
    return (filesys.open(path, .{ .CREAT = true }) catch panic("FileSystemTree.open() failed", @src()));
}

// EXTERNAL: write data to fd
export fn write(fd: u32, path_ptr: [*:0]u8) u32 {
    return filesys.write(fd, .{}, readString(path_ptr)) catch 0;
}

// EXTERNAL: read data from fd
export fn read(fd: u32) [*]u8 {
    const data: []u8 = filesys.read(fd) catch "";
    return data.ptr;
}
