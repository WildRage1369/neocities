const std = @import("std");
const builtin = @import("builtin");
const FileSystemTree = @import("fs.zig").FileSystemTree;

extern fn logNum(data: u32) void;
extern fn logStr(ptr: [*:0]const u8) void;
extern fn logErr(ptr: [*:0]const u8) void;

fn panic(msg: []const u8, e: anyerror, src: std.builtin.SourceLocation) noreturn {
    var buf: [1024:0]u8 = undefined;
    const s = std.fmt.bufPrint(buf[0..], "\t{s} {s}:{any}:{any}\n\t{any}\n\tfn {s}()", .{
        msg,
        src.file,
        src.line,
        src.column,
        e,
        src.fn_name,
    }) catch unreachable;
    std.mem.copyForwards(u8, buf[0..], s);

    buf[s.len + 1] = 0;
    if (comptime builtin.target.cpu.arch == .wasm32) logErr(buf[0..s.len :0]);
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
    const arr = wasm_alloc.alloc(u8, len + 1) catch |e| panic("allocString() failed", e, @src());
    // if (comptime builtin.target.cpu.arch == .wasm32) logStr("allocString() done".ptr);
    return arr.ptr;
}

// EXTERNAL: initializes the file system
export fn init() void {
    filesys = FileSystemTree.create(wasm_alloc) catch |e| panic("FileSystemTree.create() failed", e, @src());
    if (comptime builtin.target.cpu.arch == .wasm32) logStr("init() done".ptr);
}

// EXTERNAL: opens a file and returns a serial number
export fn open(path_ptr: [*:0]u8, flags: u8) u32 {
    var f: FileSystemTree.O_Flags = .{};
    switch (flags) {
        0b01 => f.CREAT = true,
        0b10 => f.EXCL = true,
        0b11 => {
            f.EXCL = true;
            f.CREAT = true;
        },
        else => {},
    }
    const path = readString(path_ptr);
    return (filesys.open(path, f) catch |e| panic("open() failed", e, @src()));
}

// EXTERNAL: write data to fd
export fn write(fd: u32, path_ptr: [*:0]u8) u32 {
    return filesys.write(fd, .{}, readString(path_ptr)) catch 0;
}

// EXTERNAL: read data from fd
export fn read(fd: u32) [*]u8 {
    const data: []u8 = filesys.read(fd) catch |e| panic("read() failed", e, @src());
    return data.ptr;
}

// EXTERNAL: get current working directory
export fn getcwd(fd: u32) [*]u8 {
    const data: []u8 = filesys.getcwd(fd) catch |e| panic("getcwd() failed", e, @src());
    return data.ptr;
}
