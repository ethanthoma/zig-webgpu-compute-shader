const std = @import("std");
const assert = std.debug.assert;

const App = @import("app.zig").App;

pub fn main() !void {
    // Create window
    var app = try App.init();
    defer app.deinit();

    while (app.isRunning()) {
        app.run();
    }
}
