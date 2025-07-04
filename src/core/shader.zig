const std = @import("std");
const gl = @import("zopengl").bindings;
const math = @import("math");
const Texture = @import("texture.zig").Texture;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat3 = math.Mat3;
const Mat4 = math.Mat4;

const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const ShaderError = error{
    CompileError,
    LinkError,
};

pub const Shader = struct {
    id: u32,
    vert_file: []const u8,
    frag_file: []const u8,
    geom_file: ?[]const u8,
    locations: *StringHashMap(c_int),
    allocator: Allocator,
    
    // Debug uniform collection
    debug_enabled: bool,
    debug_arena: std.heap.ArenaAllocator,
    debug_uniforms: StringHashMap([]const u8),

    const Self = @This();
    var current_shader: ?*const Shader = null;

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.vert_file);
        self.allocator.free(self.frag_file);
        if (self.geom_file != null) {
            self.allocator.free(self.geom_file.?);
        }
        gl.deleteShader(self.id);
        var iterator = self.locations.keyIterator();
        while (iterator.next()) |key| {
            self.allocator.free(key.*);
        }
        self.locations.deinit();
        self.allocator.destroy(self.locations);
        
        // Clean up debug resources
        self.debug_uniforms.deinit();
        self.debug_arena.deinit();
        
        self.allocator.destroy(self);
    }

    pub fn init(allocator: Allocator, vert_file_path: []const u8, frag_file_path: []const u8) !*Shader {
        return initWithGeom(allocator, vert_file_path, frag_file_path, null);
    }

    pub fn initWithGeom(allocator: Allocator, vert_file_path: []const u8, frag_file_path: []const u8, optional_geom_file: ?[]const u8,) !*Shader {
        const vert_file = std.fs.cwd().openFile(vert_file_path, .{}) catch |err| {
            std.debug.panic("Shader error: {any} file: {s}", .{ err, vert_file_path });
        };

        const vert_code = try vert_file.readToEndAlloc(allocator, 256 * 1024);
        const c_vert_code: [:0]const u8 = try allocator.dupeZ(u8, vert_code);

        defer vert_file.close();
        defer allocator.free(vert_code);
        defer allocator.free(c_vert_code);

        // std.debug.print("vert_code: {s}\n", .{c_vert_code});

        const vertex_shader = gl.createShader(gl.VERTEX_SHADER);
        gl.shaderSource(vertex_shader, 1, &[_][*c]const u8{c_vert_code.ptr}, 0);
        gl.compileShader(vertex_shader);

        checkCompileErrors(vertex_shader, "VERTEX");

        const frag_file = try std.fs.cwd().openFile(frag_file_path, .{});
        const frag_code = try frag_file.readToEndAlloc(allocator, 256 * 1024);
        const c_frag_code: [:0]const u8 = try allocator.dupeZ(u8, frag_code);

        defer frag_file.close();
        defer allocator.free(frag_code);
        defer allocator.free(c_frag_code);

        // std.debug.print("frag_code: {s}\n", .{c_frag_code});

        const frag_shader = gl.createShader(gl.FRAGMENT_SHADER);
        gl.shaderSource(frag_shader, 1, &[_][*c]const u8{c_frag_code.ptr}, 0);
        gl.compileShader(frag_shader);

        checkCompileErrors(frag_shader, "FRAGMENT");

        var geom_shader: ?c_uint = null;
        if (optional_geom_file) |geom_file_path| {
            const geom_file = try std.fs.cwd().openFile(geom_file_path, .{});
            const geom_code = try geom_file.readToEndAlloc(allocator, 256 * 1024);
            const c_geom_code: [:0]const u8 = try allocator.dupeZ(u8, frag_code);

            defer geom_file.close();
            defer allocator.free(geom_code);
            defer allocator.free(c_geom_code);

            geom_shader = gl.createShader(gl.GEOMETRY_SHADER);
            gl.shaderSource(geom_shader.?, 1, &[_][*c]const u8{c_geom_code.ptr}, 0);
            gl.compileShader(geom_shader.?);

            checkCompileErrors(geom_shader.?, "GEOM");
        }

        const shader_id = gl.createProgram();
        // link the first program object
        gl.attachShader(shader_id, vertex_shader);
        gl.attachShader(shader_id, frag_shader);
        if (geom_shader != null) {
            gl.attachShader(shader_id, geom_shader.?);
        }
        gl.linkProgram(shader_id);

        checkCompileErrors(shader_id, "PROGRAM");

        // delete the shaders as they're linked into our program now and no longer necessary
        gl.deleteShader(vertex_shader);
        gl.deleteShader(frag_shader);
        if (geom_shader != null) {
            gl.deleteShader(geom_shader.?);
        }

        const geom_file = if (optional_geom_file != null) blk: {
            break :blk try allocator.dupe(u8, optional_geom_file.?);
        } else null;

        const shader = try allocator.create(Shader);

        const locations = try allocator.create(StringHashMap(c_int));
        locations.* = StringHashMap(c_int).init(allocator);

        shader.* = Shader{
            .id = shader_id,
            .vert_file = try allocator.dupe(u8, vert_file_path),
            .frag_file = try allocator.dupe(u8, frag_file_path),
            .geom_file = geom_file,
            .locations = locations,
            .allocator = allocator,
            .debug_enabled = false,
            .debug_arena = std.heap.ArenaAllocator.init(allocator),
            .debug_uniforms = StringHashMap([]const u8).init(allocator),
        };

        return shader;
    }

    pub fn useShader(self: *const Shader) void {
        if (Shader.current_shader != self) {
            gl.useProgram(self.id);
            Shader.current_shader = self;
        }
    }

    pub fn useShaderWith(self: *const Shader, projection: *Mat4, view: *Mat4) void {
        self.useShader();
        self.set_mat4("projection", projection);
        self.set_mat4("view", view);
    }

    pub fn getUniformLocation(self: *const Shader, uniform: [:0]const u8, value: anytype) c_int {
        const result = self.locations.get(uniform);

        // Capture debug value if enabled
        if (self.debug_enabled) {
            self.captureDebugUniform(uniform, value);
        }

        if (result != null) {
            // Capture debug value if enabled
            return result.?;
        }

        const key = self.allocator.dupe(u8, uniform) catch unreachable;
        const loc = gl.getUniformLocation(self.id, uniform);
        self.locations.put(key, loc) catch unreachable;

        return loc;
    }

    pub fn setBool(self: *const Shader, uniform: [:0]const u8, value: bool) void {
        self.useShader();
        const v: u8 = if (value) 1 else 0;
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform1i(location, v);
        }
    }

    pub fn setInt(self: *const Shader, uniform: [:0]const u8, value: i32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform1i(location, value);
        }
    }

    pub fn setUint(self: *const Shader, uniform: [:0]const u8, value: u32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform1ui(location, value);
        }
    }

    pub fn setFloat(self: *const Shader, uniform: [:0]const u8, value: f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform1f(location, value);
        }
    }

    pub fn set2Float(self: *const Shader, uniform: [:0]const u8, value: *const [2]f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform2fv(location, 1, value);
        }
    }

    pub fn set3Float(self: *const Shader, uniform: [:0]const u8, value: *const [3]f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform3fv(location, 1, value);
        }
    }

    pub fn set4Float(self: *const Shader, uniform: [:0]const u8, value: *const [4]f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform4fv(location, 1, value);
        }
    }

    pub fn setVec2(self: *const Shader, uniform: [:0]const u8, value: *const Vec2) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform2fv(location, 1, value.asArrayPtr());
        }
    }

    pub fn setXY(self: *const Shader, uniform: [:0]const u8, x: f32, y: f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, vec2(x, y));
        if (location != -1) {
            gl.uniform2f(location, x, y);
        }
    }

    pub fn setVec3(self: *const Shader, uniform: [:0]const u8, value: *const Vec3) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform3fv(location, 1, value.asArrayPtr());
        }
    }

    pub fn setXYZ(self: *const Shader, uniform: [:0]const u8, x: f32, y: f32, z: f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, vec3(x, y, z));
        if (location != -1) {
            gl.uniform3f(location, x, y, z);
        }
    }

    pub fn setVec4(self: *const Shader, uniform: [:0]const u8, value: *const Vec4) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, value);
        if (location != -1) {
            gl.uniform4fv(location, 1, value.asArrayPtr());
        }
    }

    pub fn setXYZW(self: *const Shader, uniform: [:0]const u8, x: f32, y: f32, z: f32, w: f32) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, vec4(x, y, z, w));
        if (location != -1) {
            gl.uniform4f(location, x, y, z, w);
        }
    }

    // ------------------------------------------------------------------------
    // pub fn setMat2(self: *const Shader, uniform: [:0]const u8, mat: *const Mat2) void {
    //     const location = gl.getUniformLocation(self.id, uniform);
    //     gl.uniformMatrix2fv(location, 1, gl.FALSE, &mat);
    // }

    pub fn setMat3(self: *const Shader, uniform: [:0]const u8, mat: *const Mat3) void {
        self.useShader();
        const location = gl.getUniformLocation(self.id, uniform);
        if (location != -1) {
            gl.uniformMatrix3fv(location, 1, gl.FALSE, mat);
        }
    }

    pub fn setMat4(self: *const Shader, uniform: [:0]const u8, mat: *const Mat4) void {
        self.useShader();
        const location = self.getUniformLocation(uniform, mat);
        if (location != -1) {
            gl.uniformMatrix4fv(location, 1, gl.FALSE, mat.toArrayPtr());
        }
    }

    pub fn setTextureUnit(self: *const Shader, texture_unit: u32, gl_texture_id: u32) void {
        self.useShader();
        gl.activeTexture(gl.TEXTURE0 + texture_unit);
        gl.bindTexture(gl.TEXTURE_2D, gl_texture_id);
    }

    pub fn bindTexture(self: *const Shader, texture_unit: i32, uniform_name: [:0]const u8, gl_texture_id: u32) void {
        self.useShader();
        gl.activeTexture(gl.TEXTURE0 + @as(c_uint, @intCast(texture_unit)));
        gl.bindTexture(gl.TEXTURE_2D, gl_texture_id);
        self.setInt(uniform_name, texture_unit);
    }

    // Debug uniform collection functions
    pub fn enableDebug(self: *Self) void {
        self.debug_enabled = true;
    }

    pub fn disableDebug(self: *Self) void {
        self.debug_enabled = false;
        // Clear arena memory while retaining capacity
        _ = self.debug_arena.reset(.retain_capacity);
        self.debug_uniforms.clearAndFree();
    }

    pub fn clearDebugUniforms(self: *Self) void {
        if (self.debug_enabled) {
            _ = self.debug_arena.reset(.retain_capacity);
            self.debug_uniforms.clearAndFree();
        }
    }

    pub fn addDebugValue(self: *Self, key: []const u8, value: []const u8) void {
        if (self.debug_enabled) {
            const allocator = self.debug_arena.allocator();
            const owned_key = allocator.dupe(u8, key) catch return;
            const owned_value = allocator.dupe(u8, value) catch return;
            self.debug_uniforms.put(owned_key, owned_value) catch return;
        }
    }

    pub fn dumpDebugUniforms(self: *Self, buffer: []u8) ![]u8 {
        if (!self.debug_enabled) {
            return std.fmt.bufPrint(buffer, "Debug not enabled\n", .{});
        }

        var stream = std.io.fixedBufferStream(buffer);
        var writer = stream.writer();
        
        try writer.print("=== Shader Debug Uniforms ===\n", .{});
        try writer.print("Shader: {s} | {s}\n", .{ self.vert_file, self.frag_file });
        try writer.print("Total uniforms: {d}\n\n", .{self.debug_uniforms.count()});
        
        var iterator = self.debug_uniforms.iterator();
        while (iterator.next()) |entry| {
            try writer.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        
        return stream.getWritten();
    }

    fn captureDebugUniform(self: *const Shader, uniform: [:0]const u8, value: anytype) void {
        if (!self.debug_enabled) return;
        
        // We need to cast away const to modify the arena and hashmap for debug purposes
        const mutable_self = @as(*Shader, @ptrFromInt(@intFromPtr(self)));
        const allocator = mutable_self.debug_arena.allocator();
        var buf: [256]u8 = undefined;
        
        const value_str = switch (@TypeOf(value)) {
            bool => std.fmt.bufPrint(&buf, "{}", .{value}) catch return,
            i32 => std.fmt.bufPrint(&buf, "{d}", .{value}) catch return,
            u32 => std.fmt.bufPrint(&buf, "{d}", .{value}) catch return,
            f32 => std.fmt.bufPrint(&buf, "{d:.3}", .{value}) catch return,
            *const Vec2 => std.fmt.bufPrint(&buf, "Vec2({d:.3}, {d:.3})", .{ value.x, value.y }) catch return,
            *const Vec3 => std.fmt.bufPrint(&buf, "Vec3({d:.3}, {d:.3}, {d:.3})", .{ value.x, value.y, value.z }) catch return,
            *const Vec4 => std.fmt.bufPrint(&buf, "Vec4({d:.3}, {d:.3}, {d:.3}, {d:.3})", .{ value.x, value.y, value.z, value.w }) catch return,
            *const Mat4 => std.fmt.bufPrint(&buf, "Mat4([{d:.2}, {d:.2}, {d:.2}, {d:.2}]...)", .{ value.data[0][0], value.data[0][1], value.data[0][2], value.data[0][3] }) catch return,
            *const [2]f32 => std.fmt.bufPrint(&buf, "[{d:.3}, {d:.3}]", .{ value[0], value[1] }) catch return,
            *const [3]f32 => std.fmt.bufPrint(&buf, "[{d:.3}, {d:.3}, {d:.3}]", .{ value[0], value[1], value[2] }) catch return,
            *const [4]f32 => std.fmt.bufPrint(&buf, "[{d:.3}, {d:.3}, {d:.3}, {d:.3}]", .{ value[0], value[1], value[2], value[3] }) catch return,
            else => std.fmt.bufPrint(&buf, "{any}", .{value}) catch return,
        };
        
        const owned_key = allocator.dupe(u8, uniform) catch return;
        const owned_value = allocator.dupe(u8, value_str) catch return;
        mutable_self.debug_uniforms.put(owned_key, owned_value) catch return;
    }
};

fn checkCompileErrors(id: u32, check_type: []const u8) void {
    var infoLog: [10000]u8 = undefined;
    var successful: c_int = undefined;

    if (!std.mem.eql(u8, check_type, "PROGRAM")) {
        gl.getShaderiv(id, gl.COMPILE_STATUS, &successful);
        if (successful != gl.TRUE) {
            var len: c_int = 0;
            gl.getShaderiv(id, gl.INFO_LOG_LENGTH, &len);
            gl.getShaderInfoLog(id, 2024, null, &infoLog);
            std.debug.panic("shader {s} compile error: {s}", .{ check_type, infoLog[0..@intCast(len)] });
        }
    } else {
        gl.getProgramiv(id, gl.LINK_STATUS, &successful);
        if (successful != gl.TRUE) {
            var len: c_int = 0;
            gl.getProgramiv(id, gl.INFO_LOG_LENGTH, &len);
            gl.getProgramInfoLog(id, 2024, null, &infoLog);
            std.debug.panic("shader {s} link error: {s}", .{ check_type, infoLog[0..@intCast(len)] });
        }
    }
}
