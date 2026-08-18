const std = @import("std");
const gl = @import("zopengl").bindings;
const math = @import("math");
const containers = @import("containers");
const constants = @import("../constants.zig");
const AABB = @import("../aabb.zig").AABB;
const Shader = @import("../shader.zig").Shader;

const Allocator = std.mem.Allocator;
const ManagedArrayList = containers.ManagedArrayList;

const Vec2 = math.Vec2;
const Vec3 = math.Vec3;

const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;

const SIZE_OF_U32 = @sizeOf(u32);
const SIZE_OF_FLOAT = @sizeOf(f32);

pub const ShapeBuilder = struct {
    allocator: Allocator,
    shape_type: ShapeType,
    positions: ManagedArrayList([3]f32),
    texcoords: ManagedArrayList([2]f32),
    normals: ManagedArrayList([3]f32),
    colors: ManagedArrayList([4]f32),
    indices: ManagedArrayList(u32),
    aabb: AABB,

    const Self = @This();

    pub fn init(allocator: Allocator, shape_type: ShapeType) ShapeBuilder {
        return .{
            .allocator = allocator,
            .shape_type = shape_type,
            .positions = ManagedArrayList([3]f32).init(allocator),
            .texcoords = ManagedArrayList([2]f32).init(allocator),
            .normals = ManagedArrayList([3]f32).init(allocator),
            .colors = ManagedArrayList([4]f32).init(allocator),
            .indices = ManagedArrayList(u32).init(allocator),
            .aabb = AABB.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.positions.deinit();
        self.texcoords.deinit();
        self.normals.deinit();
        self.colors.deinit();
        self.indices.deinit();
    }

    pub fn addVertex(self: *Self, position: [3]f32, normal: [3]f32, texCoord: [2]f32) !u32 {
        const index = @as(u32, @intCast(self.positions.items().len));
        try self.positions.append(position);
        try self.normals.append(normal);
        try self.texcoords.append(texCoord);
        self.aabb.expandWithArray(position);
        return index;
    }

    pub fn addIndex(self: *Self, index: u32) !void {
        try self.indices.append(index);
    }

    pub fn resize(self: *Self, size: u32) !void {
        try self.positions.resize(size);
        try self.texcoords.resize(size);
        try self.normals.resize(size);
        try self.colors.resize(size);
    }

    pub fn build(self: *Self) !*Shape {
        return initGLBuffers(
            self.allocator,
            self.shape_type,
            self.positions.list.items,
            self.texcoords.list.items,
            self.normals.list.items,
            self.colors.list.items,
            self.indices.list.items,
        );
    }
};

pub fn initGLBuffers(
    allocator: Allocator,
    shape_type: ShapeType,
    positions: []const [3]f32,
    texcoords: []const [2]f32,
    normals: []const [3]f32,
    colors: []const [4]f32,
    indices: []const u32,
) !*Shape {
    var vao: u32 = 0;
    var position_vbo: u32 = 0;
    var texcoord_vbo: u32 = 0;
    var normal_vbo: u32 = 0;
    var color_vbo: u32 = 0;
    var ebo: u32 = 0;

    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);

    // attach buffer → fill buffer → describe layout → enable attribute.
    // 1. Create and bind the vertex buffer, VBO
    // 2. Upload data
    // 3. Configure attribute
    // 4. Enable attribute

    // positions
    gl.genBuffers(1, &position_vbo);
    gl.bindBuffer(gl.ARRAY_BUFFER, position_vbo);
    gl.bufferData(
        gl.ARRAY_BUFFER,
        @intCast(positions.len * @sizeOf([3]f32)),
        positions.ptr,
        gl.STATIC_DRAW,
    );
    gl.vertexAttribPointer(
        constants.VertexAttr.POSITION,
        3,
        gl.FLOAT,
        gl.FALSE,
        0,
        null,
    );
    gl.enableVertexAttribArray(constants.VertexAttr.POSITION);

    // texcoords
    if (texcoords.len > 0) {
        gl.genBuffers(1, &texcoord_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, texcoord_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(texcoords.len * @sizeOf([2]f32)),
            texcoords.ptr,
            gl.STATIC_DRAW,
        );
        gl.vertexAttribPointer(
            constants.VertexAttr.TEXCOORD,
            2,
            gl.FLOAT,
            gl.FALSE,
            0,
            null,
        );
        gl.enableVertexAttribArray(constants.VertexAttr.TEXCOORD);
    }

    // normals
    if (normals.len > 0) {
        gl.genBuffers(1, &normal_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, normal_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(normals.len * @sizeOf([3]f32)),
            normals.ptr,
            gl.STATIC_DRAW,
        );
        gl.vertexAttribPointer(
            constants.VertexAttr.NORMAL,
            3,
            gl.FLOAT,
            gl.FALSE,
            0,
            null,
        );
        gl.enableVertexAttribArray(constants.VertexAttr.NORMAL);
    }

    // colors
    if (colors.len > 0) {
        gl.genBuffers(1, &color_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, color_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(colors.len * @sizeOf([4]f32)),
            colors.ptr,
            gl.STATIC_DRAW,
        );
        gl.vertexAttribPointer(
            constants.VertexAttr.COLOR,
            4,
            gl.FLOAT,
            gl.FALSE,
            0,
            null,
        );
        gl.enableVertexAttribArray(constants.VertexAttr.COLOR);
    }

    // indices
    gl.genBuffers(1, &ebo);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.bufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(indices.len * @sizeOf(u32)),
        indices.ptr,
        gl.STATIC_DRAW,
    );

    const aabb = AABB.initWithPositions(positions);

    const s = try allocator.create(Shape);
    s.* = .{
        .shape_type = shape_type,
        .vao = vao,
        .vbo = position_vbo, // Primary VBO for positions
        .ebo = ebo,
        .color_vbo = color_vbo,
        .has_vertex_colors = colors.len > 0,
        .num_indices = @intCast(indices.len),
        .aabb = aabb,
    };
    return s;
}

pub const ShapeType = enum {
    square,
    plane,
    cube,
    cylinder,
    sphere,
    skybox,
    custom,
};

pub const Shape = struct {
    shape_type: ShapeType,
    vao: u32 = 0,
    vbo: u32 = 0,
    ebo: u32 = 0,
    color_vbo: u32 = 0,
    has_vertex_colors: bool = false,
    num_indices: i32 = 0,
    aabb: AABB,
    gl_texture_id: u32 = 0, // Perhaps the original type should manage these and deinit them

    /// Skip rendering entirely. Use for temporarily hiding objects.
    is_visible: bool = true,

    /// Enable alpha blending. Set true for glass, particles, transparent materials.
    /// Note: Typically pair with is_depth_write = false for proper transparency.
    is_transparent: bool = false,

    /// Draw as wireframe. Use for debugging geometry or stylized rendering.
    is_wireframe: bool = false,

    /// Disable face culling to draw both sides. Use for planes, foliage, cloth.
    is_double_sided: bool = false,

    /// Write to depth buffer. Set false for transparent objects that shouldn't occlude.
    /// Default true for normal opaque rendering.
    is_depth_write: bool = true,

    /// Test against depth buffer. Set false for skyboxes, UI overlays, debug gizmos.
    /// Default true for normal 3D objects.
    is_depth_test: bool = true,

    const Self = @This();

    pub fn deleteGlObjects(self: *Self) void {
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
        gl.deleteBuffers(1, &self.ebo);
        if (self.color_vbo != 0) {
            gl.deleteBuffers(1, &self.color_vbo);
        }
        gl.deleteTextures(1, &self.gl_texture_id);
    }

    pub fn draw(self: *const Self, shader: *Shader, instance_count: u32) void {
        if (!self.is_visible) return;

        shader.useShader();

        if (self.is_depth_test) gl.enable(gl.DEPTH_TEST) else gl.disable(gl.DEPTH_TEST);
        if (!self.is_depth_write) gl.depthMask(gl.FALSE);
        if (self.is_double_sided) gl.disable(gl.CULL_FACE);

        if (self.is_transparent) {
            gl.enable(gl.BLEND);
            gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        }

        if (self.is_wireframe) gl.polygonMode(gl.FRONT_AND_BACK, gl.LINE);

        gl.disable(gl.CULL_FACE);

        gl.bindVertexArray(self.vao);
        gl.drawElementsInstanced(
            gl.TRIANGLES,
            self.num_indices,
            gl.UNSIGNED_INT,
            null,
            @intCast(instance_count),
        );
        gl.bindVertexArray(0);

        if (self.is_wireframe) gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
        if (self.is_transparent) gl.disable(gl.BLEND);
        if (self.is_double_sided) gl.enable(gl.CULL_FACE);
        if (!self.is_depth_write) gl.depthMask(gl.TRUE);
    }
};
