const std = @import("std");
const gl = @import("zopengl").bindings;
const math = @import("math");

const Allocator = std.mem.Allocator;

const AABB = @import("../aabb.zig").AABB;

const Vec2 = math.Vec2;
const vec2 = math.vec2;
const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Vec4 = math.Vec4;
const vec4 = math.vec4;
const Mat4 = math.Mat4;

const SIZE_OF_U32 = @sizeOf(u32);
const SIZE_OF_FLOAT = @sizeOf(f32);

pub const VertexData = struct {
    positions: []const [3]f32,
    texCoords: []const [2]f32,
    normals: []const [3]f32,
    indices: []const u32,
};

pub const ShapeBuilder = struct {
    shape_type: ShapeType,
    positions: [][3]f32 = undefined,
    texCoords: [][2]f32 = undefined,
    normals: [][3]f32 = undefined,
    indices: []u32 = undefined,
    aabb: AABB,

    pub fn init(allocator: Allocator, shape_type: ShapeType) ShapeBuilder {
        _ = allocator;
        return .{
            .shape_type = shape_type,
            // .positions = std.ArrayList([3]f32).init(allocator),
            // .normals = std.ArrayList([3]f32).init(allocator),
            // .texCoords = std.ArrayList([2]f32).init(allocator),
            // .indices = std.ArrayList(u32).init(allocator),
            .aabb = AABB.init(),
        };
    }

    pub fn deinit(self: *ShapeBuilder) void {
        _ = self;
        // self.positions.deinit();
        // self.normals.deinit();
        // self.texCoords.deinit();
        // self.indices.deinit();
    }

    pub fn addVertex(self: *ShapeBuilder, position: [3]f32, normal: [3]f32, texCoord: [2]f32) !u32 {
        const index = @as(u32, @intCast(self.positions.items.len));
        try self.positions.append(position);
        try self.normals.append(normal);
        try self.texCoords.append(texCoord);
        self.aabb.expand(vec3(position[0], position[1], position[2]));
        return index;
    }

    pub fn addIndex(self: *ShapeBuilder, index: u32) !void {
        try self.indices.append(index);
    }

    // pub fn buildVertex(self: *const ShapeBuilder, allocator: Allocator) !Vertex {
    //     return Vertex{
    //         .positions = try allocator.dupe([3]f32, self.positions.items),
    //         .normals = try allocator.dupe([3]f32, self.normals.items),
    //         .texCoords = try allocator.dupe([2]f32, self.texCoords.items),
    //         .indices = try allocator.dupe(u32, self.indices.items),
    //     };
    // }

    // pub fn buildShape(self: *const ShapeBuilder, allocator: Allocator) !Shape {
    //     const vertex_data = try self.buildVertex(allocator);
    //     defer {
    //         allocator.free(vertex_data.positions);
    //         allocator.free(vertex_data.normals);
    //         allocator.free(vertex_data.texCoords);
    //         allocator.free(vertex_data.indices);
    //     }
    //     // return initGLBuffersWithType(&vertex_data, self.shape_type, self.aabb);
    // }
};

pub const ShapeType = enum {
    Cube,
    Cylinder,
    Sphere,
    Custom,
};

pub const Shape = struct {
    shape_type: ShapeType,
    aabb: AABB,
    vao: u32 = 0,
    vbo: u32 = 0,
    ebo: u32 = 0,
    num_indices: i32 = 0,
    transforms_vbo: u32,

    const Self = @This();

    pub fn init(vertex_data: *const VertexData, shape_type: ShapeType) !Shape {
        return initGLBuffers(vertex_data, shape_type);
    }

    pub fn deinit(self: *Self) void {
        gl.deleteVertexArrays(1, &self.vao);
        gl.deleteBuffers(1, &self.vbo);
    }

    pub fn draw(self: *const Self) void {
        gl.bindVertexArray(self.vao);
        gl.drawElements(
            gl.TRIANGLES,
            self.num_indices,
            gl.UNSIGNED_INT,
            null,
        );
        gl.bindVertexArray(0);
    }
    
    pub fn drawInstanced(self: *const Self, instance_count: i32, transforms: []Mat4) void {
        gl.bindVertexArray(self.vao);

        gl.bindBuffer(gl.ARRAY_BUFFER, self.transforms_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(transforms.len * @sizeOf(Mat4)),
            transforms.ptr,
            gl.STREAM_DRAW,
        );
        
        gl.drawElementsInstanced(
            gl.TRIANGLES,
            self.num_indices,
            gl.UNSIGNED_INT,
            null,
            instance_count,
        );
        gl.bindVertexArray(0);
    }
};

pub fn initGLBuffers(vertex_data: *const VertexData, shape_type: ShapeType, is_instanced: bool) Shape {
    var vao: u32 = undefined;
    var position_vbo: u32 = undefined;
    var normal_vbo: u32 = undefined;
    var texcoord_vbo: u32 = undefined;
    var transforms_vbo: u32 = undefined;
    var ebo: u32 = undefined;

    gl.genVertexArrays(1, &vao);
    gl.genBuffers(1, &position_vbo);
    gl.genBuffers(1, &normal_vbo);
    gl.genBuffers(1, &texcoord_vbo);
    gl.genBuffers(1, &ebo);

    gl.bindVertexArray(vao);

    // positions
    gl.bindBuffer(gl.ARRAY_BUFFER, position_vbo);
    gl.bufferData(
        gl.ARRAY_BUFFER,
        @intCast(vertex_data.positions.len * @sizeOf([3]f32)),
        vertex_data.positions.ptr,
        gl.STATIC_DRAW,
    );
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 0, null);
    gl.enableVertexAttribArray(0);

    // texcoords
    if (vertex_data.texCoords.len > 0) {
        gl.bindBuffer(gl.ARRAY_BUFFER, texcoord_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(vertex_data.texCoords.len * @sizeOf([2]f32)),
            vertex_data.texCoords.ptr,
            gl.STATIC_DRAW,
        );
        gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 0, null);
        gl.enableVertexAttribArray(1);
    }

    // normals
    if (vertex_data.normals.len > 0) {
        gl.bindBuffer(gl.ARRAY_BUFFER, normal_vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @intCast(vertex_data.normals.len * @sizeOf([3]f32)),
            vertex_data.normals.ptr,
            gl.STATIC_DRAW,
        );
        gl.vertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, 0, null);
        gl.enableVertexAttribArray(2);
    }

    // indices
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
    gl.bufferData(
        gl.ELEMENT_ARRAY_BUFFER,
        @intCast(vertex_data.indices.len * @sizeOf(u32)),
        vertex_data.indices.ptr,
        gl.STATIC_DRAW,
    );

    if (is_instanced) {
        // Per instance transform matrix (locations 2, 3, 4, 5)
        gl.genBuffers(1, &transforms_vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, transforms_vbo);
        // Mat4 is 4 Vec4s, so we need 4 attribute locations
        for (0..4) |i| {
            const location: c_uint = @intCast(3 + i);
            gl.enableVertexAttribArray(location);
            gl.vertexAttribPointer(
                location,
                4,
                gl.FLOAT,
                gl.FALSE,
                @sizeOf(math.Mat4),
                @ptrFromInt(i * @sizeOf(math.Vec4)),
            );
            // one matrix per instance
            gl.vertexAttribDivisor(location, 1);
        }
    }

    const aabb = AABB.initWithPositions(vertex_data.positions);

    return .{
        .shape_type = shape_type,
        .vao = vao,
        .vbo = position_vbo, // Primary VBO for positions
        .ebo = ebo,
        .num_indices = @intCast(vertex_data.indices.len),
        .transforms_vbo = transforms_vbo,
        .aabb = aabb,
    };
}
