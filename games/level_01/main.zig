const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const gl = @import("zopengl").bindings;
const core = @import("core");
const math = @import("math");

const run_app = @import("run_app.zig").run;
const run_animation = @import("test_animation.zig").run;

const SCR_WIDTH: f32 = 1000.0;
const SCR_HEIGHT: f32 = 1000.0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    core.string.init(allocator);

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);
    glfw.windowHint(.opengl_forward_compat, true);

    const window = try glfw.Window.create(
        SCR_WIDTH,
        SCR_HEIGHT,
        "Level 01",
        null,
    );
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);
    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    try run_app(allocator, window);
    try run_animation(allocator, window);

    glfw.terminate();

    // testMovementMatrix();
}

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Quat = math.Quat;
const Mat4 = math.Mat4;
var buffer1: [1024]u8 = undefined;
var buffer2: [1024]u8 = undefined;

fn testMovementMatrix() void {
    std.debug.print("\n=== Simple Step-by-Step Movement ===\n", .{});

    // Step 1: Define starting position
    const start_position = math.vec3(0.0, 0.0, 0.0);
    std.debug.print("Step 1 - Start position: {s}\n", .{start_position.asString(&buffer1)});

    // Step 2: Define direction (normalized)
    const direction = math.vec3(1.0, 1.0, 0.0).toNormalized();
    std.debug.print("Step 2 - Direction (normalized): {s}\n", .{direction.asString(&buffer1)});

    // Step 3: Move along direction by different distances
    const distances = [_]f32{ 0.0, 10.0, 20.0, 30.0, 40.0 };

    std.debug.print("Step 3 - Moving along direction:\n", .{});
    for (distances, 0..) |distance, i| {
        // Step 4: Scale direction by distance
        const offset = direction.mulScalar(distance);

        // Step 5: Add offset to starting position
        const new_position = start_position.add(&offset);

        std.debug.print("  Frame {}: distance={:.1} -> position={s}\n", .{ i, distance, new_position.asString(&buffer1) });
    }

    testMultipleObjects();
}

fn testMultipleObjects() void {

    std.debug.print("\n=== Array-Based Approach for Multiple Objects ===\n", .{});
    // Multiple starting positions
    const start_positions = [_]math.Vec3{
        math.vec3(0.0, 0.0, 0.0),
        math.vec3(10.0, 0.0, 0.0),
        math.vec3(0.0, 10.0, 0.0),
    };

    // Multiple directions (normalized)
    const directions = [_]math.Vec3{
        math.vec3(1.0, 0.0, 0.0).toNormalized(),
        math.vec3(0.0, 1.0, 0.0).toNormalized(),
        math.vec3(1.0, 1.0, 0.0).toNormalized(),
    };

    // Current distance each object has traveled
    var distances = [_]f32{ 0.0, 5.0, 10.0 };

    // Simulate 3 animation frames
    const frames = 3;
    const distance_per_frame = 5.0;

    var frame: u32 = 0;
    while (frame < frames) {
        std.debug.print("Frame {d}:\n", .{frame});

        // Update each object's position
        for (start_positions, directions, &distances, 0..) |start_pos, dir, *distance, i| {
            // Step 1: Scale direction by current distance
            const offset = dir.mulScalar(distance.*);

            // Step 2: Calculate new position
            const new_position = start_pos.add(&offset);

            std.debug.print("  Object {}: distance={:.1} -> position={s}\n", .{ i, distance.*, new_position.asString(&buffer1) });

            // Step 3: Increase distance for next frame
            distance.* += distance_per_frame;
        }

        frame += 1;
        std.debug.print("\n", .{});
    }

    std.debug.print("=== For Shader Usage ===\n", .{});
    std.debug.print("Pass arrays of:\n", .{});
    std.debug.print("- start_positions[]: Starting positions for each instance\n", .{});
    std.debug.print("- directions[]: Normalized directions for each instance\n", .{});
    std.debug.print("- distances[]: Current travel distance for each instance\n", .{});
    std.debug.print("In vertex shader: new_position = start_position + (direction * distance)\n", .{});

    testModelMovement();
}

fn testModelMovement() void {
    std.debug.print("\n=== 3D Model Movement with Orientation ===\n", .{});

    // Starting positions for 3D models
    const model_positions = [_]math.Vec3{
        math.vec3(0.0, 0.0, 0.0),
        math.vec3(5.0, 0.0, 0.0),
        math.vec3(10.0, 0.0, 0.0),
    };

    // Movement directions (arbitrary 3D directions, normalized)
    const movement_directions = [_]math.Vec3{
        math.vec3(1.0, 1.0, 0.0).toNormalized(), // Moving up-forward-right
        //math.vec3(1.0, 0.5, 0.2).toNormalized(), // Moving up-forward-right
        math.vec3(-0.5, -1.0, 0.7).toNormalized(), // Moving down-back-right
        math.vec3(0.3, 0.8, -0.4).toNormalized(), // Moving up-left
    };

    // Travel distances for animation frames
    const travel_distances = [_]f32{ 0.0, 3.0, 6.0, 9.0, 12.0 };

    std.debug.print("Creating transform matrices for 3D models:\n", .{});

    for (model_positions, movement_directions, 0..) |start_pos, dir, model_i| {
        std.debug.print("\nModel {d} - Moving through distances:\n", .{model_i});

        for (travel_distances, 0..) |distance, frame| {
            std.debug.print("  Frame {d} (distance={d}):\n", .{ frame, distance });

            // Step 1: Calculate new position
            const offset = dir.mulScalar(distance);
            const new_position = start_pos.add(&offset);
            const translation = math.Mat4.fromTranslation(&new_position);

            // Step 3: Calculate rotation to align model with arbitrary 3D direction
            // Assuming model's default forward is along +Z axis, up is +Y
            const model_forward = math.vec3(0.0, 0.0, 1.0);
            const world_up = math.vec3(0.0, 1.0, 0.0);

            // Step 4: Create lookAt orientation quaternion
            const look_quat = math.Quat.lookAtOrientation(model_forward, dir, world_up);
            const rotation = math.Mat4.fromQuat(&look_quat);

            // Step 5: Combine rotation and translation into final transform matrix
            const transform = rotation.mulMat4(&translation);

            std.debug.print("    Position: {s} -> {s}\n", .{ start_pos.asString(&buffer1), new_position.asString(&buffer2) });
            std.debug.print("    Direction: {s}\n", .{dir.asString(&buffer1)});
            std.debug.print("    Transform matrix: {s}\n", .{transform.asString(&buffer1)});
        }
        
        std.debug.print("  Model {d} completed all movement frames\n", .{model_i});
    }

    std.debug.print("\n=== For 3D Model Shader Usage (Arbitrary Directions) ===\n", .{});
    std.debug.print("1. Calculate position: new_pos = start_pos + (direction * distance)\n", .{});
    std.debug.print("2. Create translation matrix: T = translate(new_pos)\n", .{});
    std.debug.print("3. Calculate rotation: quat = lookAtOrientation(model_forward, direction, world_up)\n", .{});
    std.debug.print("4. Convert to matrix: R = Mat4.fromQuat(quat)\n", .{});
    std.debug.print("5. Final transform: model_matrix = R * T\n", .{});
    std.debug.print("6. In vertex shader: gl_Position = projection * view * model_matrix * vertex_pos\n", .{});
}
