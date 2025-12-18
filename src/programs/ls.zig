const Self = @This();
const std = @import("std");

extern fn logStr(ptr: [*:0]const u8) void;

pub fn ls(args: [*:0]const u8)  callconv(.c) void {
    logStr(std.mem.span(args));
    return;
}
