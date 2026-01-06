const std = @import("std");
const gl = @import("zopengl").bindings;
const math = @import("math");
const Shader = @import("../shader.zig").Shader;
const Color = @import("../colors.zig").Color;

const Allocator = std.mem.Allocator;

const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

/// Represents a single line segment to be drawn
pub const LineSegment = struct {
    start: Vec3,
    end: Vec3,
    color: Color,
    alpha: ?f32 = null, // If null, uses Lines.default_alpha
};

/// Line rendering system for drawing colored line segments
pub const Lines = struct {
    vao: c_uint,
    vbo: c_uint,
    shader: *Shader,
    thickness: f32,
    default_alpha: f32,
    max_lines: usize,
    vertices: []f32,

    const Self = @This();

    /// Initialize the line drawing system
    /// thickness: Line width in pixels
    /// default_alpha: Default alpha value for lines (0.0-1.0)
    /// max_lines: Maximum number of lines that can be drawn in a single batch
    pub fn init(allocator: Allocator, shader: *Shader, thickness: f32, default_alpha: f32, max_lines: usize) !Self {
        var vao: u32 = 0;
        var vbo: u32 = 0;

        // Generate VAO and VBO
        gl.genVertexArrays(1, &vao);
        gl.genBuffers(1, &vbo);

        gl.bindVertexArray(vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, vbo);

        // Allocate buffer for max_lines (2 vertices per line, 7 floats per vertex: 3 pos + 4 RGBA)
        const buffer_size = max_lines * 2 * 7 * @sizeOf(f32);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(buffer_size), null, gl.DYNAMIC_DRAW);

        // Position attribute (location 0)
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 7 * @sizeOf(f32), null);
        gl.enableVertexAttribArray(0);

        // Color attribute (location 1) - now RGBA
        const color_offset: ?*const anyopaque = @ptrFromInt(3 * @sizeOf(f32));
        gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, 7 * @sizeOf(f32), color_offset);
        gl.enableVertexAttribArray(1);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
        gl.bindVertexArray(0);

        // Build vertex data (7 floats per vertex: 3 pos + 4 RGBA)
        const vertices = try allocator.alloc(f32, max_lines * 2 * 7);

        const lines = Self{
            .vao = vao,
            .vbo = vbo,
            .shader = shader,
            .thickness = thickness,
            .default_alpha = default_alpha,
            .max_lines = max_lines,
            .vertices = vertices,
        };

        return lines;
    }

    /// Draw an array of line segments
    pub fn draw(self: *Self, segments: []const LineSegment, projection: *const Mat4, view: *const Mat4) void {
        if (segments.len == 0) return;
        if (segments.len > self.max_lines) {
            std.debug.print("Warning: Trying to draw {} lines but max is {}. Drawing first {} lines.\n", .{ segments.len, self.max_lines, self.max_lines });
        }

        const num_lines = @min(segments.len, self.max_lines);

        var idx: usize = 0;
        for (segments[0..num_lines]) |segment| {
            const color = segment.color.toRgb();
            const alpha = segment.alpha orelse self.default_alpha;

            // Start vertex
            self.vertices[idx + 0] = segment.start.x;
            self.vertices[idx + 1] = segment.start.y;
            self.vertices[idx + 2] = segment.start.z;
            self.vertices[idx + 3] = color[0];
            self.vertices[idx + 4] = color[1];
            self.vertices[idx + 5] = color[2];
            self.vertices[idx + 6] = alpha;

            // End vertex
            self.vertices[idx + 7] = segment.end.x;
            self.vertices[idx + 8] = segment.end.y;
            self.vertices[idx + 9] = segment.end.z;
            self.vertices[idx + 10] = color[0];
            self.vertices[idx + 11] = color[1];
            self.vertices[idx + 12] = color[2];
            self.vertices[idx + 13] = alpha;

            idx += 14;
        }

        // Upload vertex data
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, @intCast(self.vertices.len * @sizeOf(f32)), self.vertices.ptr);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        // Set line width
        gl.lineWidth(self.thickness);

        // Draw lines
        self.shader.useShader();
        self.shader.setMat4("projection", projection);
        self.shader.setMat4("view", view);

        gl.bindVertexArray(self.vao);
        gl.drawArrays(gl.LINES, 0, @intCast(num_lines * 2));
        gl.bindVertexArray(0);

        // Reset line width
        gl.lineWidth(1.0);
    }

    /// Clean up OpenGL resources
    pub fn deinit(self: *Self) void {
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
        self.allocator.free(self.vertices);
    }
};

/// Lightweight line drawing system with minimal setup
/// Draws one line at a time without batching
pub const SimpleLines = struct {
    vao: c_uint,
    vbo: c_uint,
    shader: Shader,

    const Self = @This();

    /// Initialize the simple line drawing system
    pub fn init(shader: Shader) !Self {
        var simple_lines = Self{
            .vao = 0,
            .vbo = 0,
            .shader = shader,
        };

        // Generate VAO and VBO
        gl.genVertexArrays(1, &simple_lines.vao);
        gl.genBuffers(1, &simple_lines.vbo);

        gl.bindVertexArray(simple_lines.vao);
        gl.bindBuffer(gl.ARRAY_BUFFER, simple_lines.vbo);

        // Allocate buffer for single line (2 vertices, 7 floats per vertex: 3 pos + 4 RGBA)
        const buffer_size = 2 * 7 * @sizeOf(f32);
        gl.bufferData(gl.ARRAY_BUFFER, @intCast(buffer_size), null, gl.DYNAMIC_DRAW);

        // Position attribute (location 0)
        gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 7 * @sizeOf(f32), null);
        gl.enableVertexAttribArray(0);

        // Color attribute (location 1) - RGBA
        const color_offset: ?*const anyopaque = @ptrFromInt(3 * @sizeOf(f32));
        gl.vertexAttribPointer(1, 4, gl.FLOAT, gl.FALSE, 7 * @sizeOf(f32), color_offset);
        gl.enableVertexAttribArray(1);

        gl.bindBuffer(gl.ARRAY_BUFFER, 0);
        gl.bindVertexArray(0);

        return simple_lines;
    }

    /// Draw a single line segment
    pub fn drawLine(
        self: *Self,
        start: Vec3,
        end: Vec3,
        color: Color,
        alpha: f32,
        thickness: f32,
        projection: *const Mat4,
        view: *const Mat4,
    ) void {
        const rgb = color.toRgb();

        // Build vertex data for single line
        const vertices = [_]f32{
            // Start vertex
            start.x, start.y, start.z,
            rgb[0],  rgb[1],  rgb[2],
            alpha,
            // End vertex
              end.x,   end.y,
            end.z,   rgb[0],  rgb[1],
            rgb[2],  alpha,
        };

        // Upload vertex data
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, @intCast(vertices.len * @sizeOf(f32)), &vertices);
        gl.bindBuffer(gl.ARRAY_BUFFER, 0);

        // Set line width
        gl.lineWidth(thickness);

        // Draw line
        self.shader.useShader();
        self.shader.setMat4("projection", projection);
        self.shader.setMat4("view", view);

        gl.bindVertexArray(self.vao);
        gl.drawArrays(gl.LINES, 0, 2);
        gl.bindVertexArray(0);

        // Reset line width
        gl.lineWidth(1.0);
    }

    /// Clean up OpenGL resources
    pub fn deinit(self: *Self) void {
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
    }
};

// Simple line vertex shader
const line_vertex_shader =
    \\#version 410 core
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec4 aColor;
    \\
    \\out vec4 vertexColor;
    \\
    \\uniform mat4 projection;
    \\uniform mat4 view;
    \\
    \\void main()
    \\{
    \\    vertexColor = aColor;
    \\    gl_Position = projection * view * vec4(aPos, 1.0);
    \\}
;

// Simple line fragment shader
const line_fragment_shader =
    \\#version 410 core
    \\in vec4 vertexColor;
    \\out vec4 FragColor;
    \\
    \\void main()
    \\{
    \\    FragColor = vertexColor;
    \\}
;
