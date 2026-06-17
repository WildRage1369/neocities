const Self = @This();
extern fn createWindow(pid: u32, title: [*:0]const u8, basename: [*:0]const u8, width: u32, height: u32, x: u32, y: u32) u32;
extern fn insertFile(pid: u32, wid: u32, content: [*:0]const u8) void;

export fn main(pid: u32) callconv(.c) void {
    const wid = createWindow(pid,  "About Me", "abtme", 200, 300, 150, 150);
    insertFile(pid,wid, "programs/about_me.html");
    return;
}
