const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");

const bullets_mod = @import("bullets_matrix.zig");
const state_mod = @import("state.zig");
const Floor = @import("floor.zig").Floor;

const gl = zopengl.bindings;
const Camera = core.Camera;
const Shader = core.Shader;

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat4 = math.Mat4;

const State = state_mod.State;
const BulletStore = bullets_mod.BulletStore;

const log = std.log.scoped(.BulletsApp);

const VIEW_PORT_WIDTH: f32 = 1000.0;
const VIEW_PORT_HEIGHT: f32 = 1000.0;

// Lighting constants
const NON_BLUE: f32 = 0.9;

var state: State = undefined;

pub fn run_app(window: *glfw.Window, max_duration: ?f32) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    log.info("Starting bullets test app", .{});

    const window_size = window.getSize();
    const window_scale = window.getContentScale();
    const viewport_width = @as(f32, @floatFromInt(window_size[0])) * window_scale[0];
    const viewport_height = @as(f32, @floatFromInt(window_size[1])) * window_scale[1];
    const scaled_width = viewport_width / window_scale[0];
    const scaled_height = viewport_height / window_scale[1];

    // Initialize camera positioned to view bullet patterns
    const camera = try Camera.init(
        allocator,
        .{
            .position = vec3(0.0, 0.0, 15.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = scaled_width,
            .scr_height = scaled_height,
        },
    );
    defer camera.deinit();

    // Initialize state
    state = State{
        .viewport_width = viewport_width,
        .viewport_height = viewport_height,
        .scaled_width = scaled_width,
        .scaled_height = scaled_height,
        .window_scale = window_scale,
        .camera = camera,
        .projection = camera.getProjectionMatrix(),
        .light_position = vec3(10.0, 10.0, -30.0),
        .delta_time = 0.0,
        .total_time = 0.0,
        .world_point = null,
        .camera_initial_position = vec3(0.0, 5.0, 15.0),
        .camera_initial_target = vec3(0.0, 0.0, 0.0),
        .input = .{
            .first_mouse = true,
            .mouse_x = scaled_width / 2.0,
            .mouse_y = scaled_height / 2.0,
            .key_presses = std.EnumSet(glfw.Key).initEmpty(),
            .key_processed = std.EnumSet(glfw.Key).initEmpty(),
        },
        .animation_id = -1,
        .current_model_index = 0,
    };

    state_mod.state = &state;
    state_mod.initWindowHandlers(window);

    // Screenshot system removed for simplicity

    var plane = try core.shapes.createCube(
        .{
            .width = 100.0,
            .height = 2.0,
            .depth = 100.0,
            .num_tiles_x = 50.0,
            .num_tiles_y = 1.0,
            .num_tiles_z = 50.0,
        },
    );
    defer plane.deinit();

    const floor = try Floor.init(&arena);

    // const texture_diffuse = core.texture.TextureConfig{
    //     .filter = .Linear,
    //     .flip_v = false,
    //     .gamma_correction = false,
    //     .wrap = .Repeat,
    // };

    // const surface_texture = try core.texture.Texture.initFromFile(
    //     &arena,
    //     "/Users/john/Dev/Dev_Rust/learn_opengl_with_rust/resources/textures/window.png",
    //     //"assets/texturest/IMGP5487_seamless.jpg",
    //     texture_diffuse,
    // );

    const basic_texture_shader = try Shader.init(
        allocator,
        "examples/bullets/shaders/basic_texture.vert",
        "examples/bullets/shaders/basic_texture.frag",
    );
    defer basic_texture_shader.deinit();

    const basic_model_shader = try Shader.init(
        allocator,
        "examples/bullets/shaders/basic_model.vert",
        "examples/bullets/shaders/basic_model.frag",
    );
    defer basic_model_shader.deinit();

    // Create shaders for bullet rendering
    const bullet_shader = try Shader.init(
        allocator,
        "examples/bullets/shaders/instanced_matrix.vert",
        "examples/bullets/shaders/basic_model.frag",
    );
    defer bullet_shader.deinit();

    log.info("Bullet shader loaded: {d}", .{bullet_shader.id});

    // Unit square used for bullet impacts
    const unit_square_vao = createUnitSquareVao();

    const cubemap_texture = try core.texture.Texture.initFromFile(
        &arena,
        // "angrybots_assets/Textures/Bullet/bullet_texture_transparent.png",
        // "assets/Textures/cubemap_template_3x2.png",
        "assets/Textures/cubemap_template_2x3.png",
        // "assets/Textures/grass_block_2.png",
        // "assets/Textures/container.jpg",
        .{
            .flip_v = false,
            .gamma_correction = false,
            .filter = .Linear,
            .wrap = .Clamp,
        },
    );

    const config = core.shapes.CubeConfig{
        .width = 1.0,
        .height = 1.0,
        .depth = 1.0,
        .num_tiles_x = 1.0,
        .num_tiles_y = 1.0,
        .num_tiles_z = 1.0,
        .texture_mapping = .Cubemap2x3,
    };
    const cube = try core.shapes.createCube(config);

    // Initialize bullet store
    var bullet_store = try BulletStore.init(&arena, unit_square_vao);
    defer bullet_store.deinit();

    log.info("Bullet store initialized", .{});

    // Setup lighting
    const ambient_color = vec3(NON_BLUE * 0.7, NON_BLUE * 0.7, 0.7);
    const light_color = vec3(NON_BLUE * 0.406, NON_BLUE * 0.723, 1.0);

    bullet_shader.useShader();
    bullet_shader.setVec3("ambient", &ambient_color);
    bullet_shader.setVec3("lightColor", &light_color);
    bullet_shader.setVec3("lightDir", &vec3(-1.0, -1.0, -1.0).toNormalized());
    bullet_shader.setBool("hasTexture", true);

    basic_texture_shader.setVec3("ambientColor", &vec3(1.0, 0.6, 0.6));
    basic_texture_shader.setVec3("lightColor", &vec3(0.35, 0.4, 0.5));
    basic_texture_shader.setVec3("lightDirection", &vec3(3.0, 3.0, 3.0));
    basic_texture_shader.setBool("hasTexture", true);
    basic_texture_shader.setFloat("colorAlpha", 0.8);

    const plane_transform = Mat4.fromTranslation(&vec3(0.0, 0.0, 0.0));
    basic_texture_shader.setMat4("matModel", &plane_transform);

    // Main loop
    const start_time: f32 = @floatCast(glfw.getTime());
    var last_bullet_time: f32 = 0.0;
    const bullet_fire_interval: f32 = 2.0; // Fire bullets every second for testing

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    log.info("Starting main loop", .{});

    while (!window.shouldClose()) {
        const current_time: f32 = @floatCast(glfw.getTime());
        state.delta_time = current_time - state.total_time;
        state.total_time = current_time;

        // Check for max duration
        if (max_duration) |duration| {
            if (current_time - start_time >= duration) {
                log.info("Reached maximum duration of {d} seconds, exiting", .{duration});
                break;
            }
        }

        glfw.pollEvents();
        state_mod.processKeys();

        // Clear screen
        gl.clearColor(0.1, 0.1, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        // Screenshot system removed for simplicity

        // Auto-fire bullets for testing patterns
        if (state.run_animation and (current_time - last_bullet_time >= bullet_fire_interval)) {
            // Fire bullets in 8 directions for full 360° coverage in 45° steps
            const test_directions = [_]f32{ 0.0, math.pi / 4.0, math.pi / 2.0, 3.0 * math.pi / 4.0, math.pi, 5.0 * math.pi / 4.0, 3.0 * math.pi / 2.0, 7.0 * math.pi / 4.0 };
            const aim_angle = test_directions[state.direction_index];

            // Create transform for bullet spawn
            const spawn_position = vec3(0.0, 0.0, 0.0);
            const muzzle_transform = Mat4.fromTranslation(&spawn_position);

            _ = bullet_store.createBullets(aim_angle, &muzzle_transform);
            log.info("Fired bullets at angle: {d:.2} radians ({d:.1} degrees)", .{ aim_angle, math.radiansToDegrees(aim_angle) });

            last_bullet_time = current_time;
        }

        // Update bullets
        if (state.run_animation) {
            bullet_store.updateBullets(&state);
        }

        basic_texture_shader.bindTextureAuto("textureDiffuse", cubemap_texture.gl_texture_id);
        cube.draw();

        // Update camera and projection
        state.view = state.camera.getViewMatrix();
        const projection_view = state.projection.mulMat4(&state.view);

        bullet_store.drawBullets(bullet_shader, &projection_view);

        basic_texture_shader.setMat4("matProjection", &state.projection);
        basic_texture_shader.setMat4("matView", &state.view);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        // gl.depthMask(gl.FALSE);
        gl.disable(gl.CULL_FACE);

        // plane.render();
        floor.draw(basic_texture_shader);

        gl.disable(gl.BLEND);
        gl.enable(gl.CULL_FACE);
        // gl.depthMask(gl.TRUE);

        window.swapBuffers();
    }

    log.info("Bullets test app completed", .{});
}

fn createUnitSquareVao() gl.Uint {
    const vertices = [_]f32{
        // Positions    // Texture coords
        -0.5, -0.5, 0.0, 0.0, 0.0,
        0.5,  -0.5, 0.0, 1.0, 0.0,
        0.5,  0.5,  0.0, 1.0, 1.0,
        0.5,  0.5,  0.0, 1.0, 1.0,
        -0.5, 0.5,  0.0, 0.0, 1.0,
        -0.5, -0.5, 0.0, 0.0, 0.0,
    };

    var vao: gl.Uint = 0;
    var vbo: gl.Uint = 0;

    gl.genVertexArrays(1, &vao);
    gl.genBuffers(1, &vbo);

    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, vertices.len * @sizeOf(f32), &vertices, gl.STATIC_DRAW);

    // Position attribute
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), null);

    // Texture coordinate attribute
    gl.enableVertexAttribArray(1);
    gl.vertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));

    gl.bindVertexArray(0);

    return vao;
}
