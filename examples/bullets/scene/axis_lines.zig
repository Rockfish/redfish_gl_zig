const std = @import("std");
const core = @import("core");
const math = @import("math");

const Allocator = std.mem.Allocator;
const Shader = core.Shader;
const Lines = core.shapes.Lines;
const Color = core.Color;
const Transform = core.Transform;
const Movement = core.Movement;
const LineSegment = core.shapes.LineSegment;
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;
const vec3 = math.vec3;

// World unit axis for right handed coordinates
// x: right, red; y: up, green; -z: forward, blue
// World axes - origin at (0,0,0), unit length
const world_axis = [_]LineSegment{
    .{ .start = vec3(-10.0, 0.0, 0.0), .end = vec3(10.0, 0.0, 0.0), .color = .red },
    .{ .start = vec3(0.0, -10.0, 0.0), .end = vec3(0.0, 10.0, 0.0), .color = .green },
    .{ .start = vec3(0.0, 0.0, 10.0), .end = vec3(0.0, 0.0, -10.0), .color = .blue },
};

// Local unit axis for right handed coordinates
// x: right, violet; y: up, turquoise; z: forward, cyan
// Local axes - template that will be transformed
const local_axis = [_]LineSegment{
    .{ .start = vec3(0.0, 0.0, 0.0), .end = vec3(1.0, 0.0, 0.0), .color = .violet },
    .{ .start = vec3(0.0, 0.0, 0.0), .end = vec3(0.0, 1.0, 0.0), .color = .turquoise },
    .{ .start = vec3(0.0, 0.0, 0.0), .end = vec3(0.0, 0.0, 1.0), .color = .cyan },
};

const WorldAxis = struct {
    lines: [3]LineSegment,
    is_visible: bool,
};

const LocalAxis = struct {
    lines: [3]LineSegment,
    movement: Movement,
    is_visible: bool,
};

pub const AxisLines = struct {
    allocator: Allocator,
    world_axis: WorldAxis,
    local_axis: LocalAxis,
    lines: Lines,
    shader: *Shader,

    const Self = @This();

    pub fn init(allocator: Allocator) !Self {
        const shader = try Shader.init(
            allocator,
            "examples/bullets/shaders/lines.vert",
            "examples/bullets/shaders/lines.frag",
        );

        const lines = try Lines.init(allocator, shader, 10.0, 1.0, 3);

        return Self{
            .world_axis = .{
                .lines = world_axis,
                .is_visible = true,
            },
            .local_axis = .{
                .lines = local_axis,
                .movement = Movement.init(vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0)),
                .is_visible = true,
            },
            .lines = lines,
            .allocator = allocator,
            .shader = shader,
        };
    }

    pub fn draw(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        self.drawWorldAxis(projection, view);
        // self.drawLocalAxis(projection, view);
    }

    pub fn drawWorldAxis(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        if (!self.world_axis.is_visible) {
            return;
        }

        self.lines.draw(&self.world_axis.lines, projection, view);
    }

    pub fn drawLocalAxis(self: *Self, projection: *const Mat4, view: *const Mat4) void {
        if (!self.local_axis.is_visible) {
            return;
        }

        const position = self.local_axis.movement.transform.translation;
        const rotation = self.local_axis.movement.transform.rotation;

        var transformed: [3]LineSegment = undefined;

        // Transform each local axis by the object's transform
        for (self.local_axis.lines, 0..) |axis, i| {
            const direction = rotation.rotateVec(&axis.end);
            transformed[i] = .{
                .start = position,
                .end = position.add(&direction),
                .color = axis.color,
            };
        }

        self.lines.draw(&transformed, projection, view);
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
    }
};
