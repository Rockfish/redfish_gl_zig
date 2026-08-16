//! GL error checking for development builds.
//!
//! `glGetError` returns an undifferentiated queue with no attribution, so a single
//! check per frame only reveals that something failed, not where. Call `check()` at
//! render pass boundaries to narrow the window to one pass.
//!
//! Every call is a synchronous round-trip that can stall the driver pipeline. Pass
//! granularity (roughly a dozen per frame) is cheap; per-draw or per-uniform calls
//! are not. Compiles to nothing in ReleaseFast and ReleaseSmall.

const std = @import("std");
const builtin = @import("builtin");
const gl = @import("zopengl").bindings;

/// Max errors drained per call. GL may have several pending; this bounds the loop
/// in case a context is lost and `getError` never returns NO_ERROR.
const max_drain = 8;

pub const enabled = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;

/// Drain and report any pending GL errors, tagging them with `label`.
/// Compiles out entirely when `enabled` is false.
pub fn check(label: []const u8) void {
    if (!enabled) return;

    for (0..max_drain) |_| {
        const code = gl.getError();
        if (code == gl.NO_ERROR) {
            return;
        }
        std.debug.print("GL error at {s}: {s} (0x{X})\n", .{ label, errorName(code), code });
    }
}

fn errorName(code: gl.Enum) []const u8 {
    return switch (code) {
        gl.INVALID_ENUM => "GL_INVALID_ENUM",
        gl.INVALID_VALUE => "GL_INVALID_VALUE",
        gl.INVALID_OPERATION => "GL_INVALID_OPERATION",
        gl.INVALID_FRAMEBUFFER_OPERATION => "GL_INVALID_FRAMEBUFFER_OPERATION",
        gl.OUT_OF_MEMORY => "GL_OUT_OF_MEMORY",
        else => "unknown",
    };
}
