const Self = @This();
extern fn createWindow(title: [*:0]const u8, basename: [*:0]const u8, width: u32, height: u32, x: u32, y: u32) u32;
extern fn insertFile(wid: u32, content: [*:0]const u8) void;

export fn main() callconv(.c) void {
    const wid = createWindow("About Me", "abtme", 200, 300, 150, 150);
    insertFile(wid, "programs/about_me.html".ptr);
    return;
}
