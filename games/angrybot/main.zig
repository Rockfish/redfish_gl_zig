const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
const world = @import("state.zig");

const ArrayList = std.ArrayList;
const EnumSet = std.EnumSet;

const gl = zopengl.bindings;

const Vec3 = math.Vec3;
const vec2 = math.vec2;
const vec3 = math.vec3;
const vec4 = math.vec4;
const Mat4 = math.Mat4;

const State = world.State;
const CameraType = world.CameraType;
const Player = @import("player.zig").Player;
const Enemy = @import("enemy.zig").Enemy;
const EnemySystem = @import("enemy.zig").EnemySystem;
const BulletStore = @import("bullets.zig").BulletStore;
const BurnMarks = @import("burn_marks.zig").BurnMarks;
const MuzzleFlash = @import("muzzle_flash.zig").MuzzleFlash;
const Floor = @import("floor.zig").Floor;
const fb = @import("framebuffers.zig");
const quads = @import("quads.zig");

const Camera = core.Camera;
const Shader = core.Shader;
const SoundEngine = core.SoundEngine;

const log = std.log.scoped(.Main);

const Window = glfw.Window;

const VIEW_PORT_WIDTH: f32 = 1500.0;
const VIEW_PORT_HEIGHT: f32 = 1000.0;

// Lighting
const LIGHT_FACTOR: f32 = 0.8;
const NON_BLUE: f32 = 0.9;
const BLUR_SCALE: i32 = 2;
const FLOOR_LIGHT_FACTOR: f32 = 0.35;
const FLOOR_NON_BLUE: f32 = 0.7;


const PV = struct {
    projection: Mat4,
    view: Mat4,
};

var state: State = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    // var arena = std.heap.ArenaAllocator.init(allocator);
    // defer arena.deinit();

    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);

    const window = try glfw.Window.create(VIEW_PORT_WIDTH, VIEW_PORT_HEIGHT, "Angry Monsters", null);
    defer window.destroy();

    glfw.makeContextCurrent(window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    try run(allocator, window);

    log.info("Exiting main", .{});
}

pub fn run(allocator: std.mem.Allocator, window: *glfw.Window) !void {
    var buf: [512]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&buf);
    // const cwd = try std.os.getFdPath(&buf);
    log.info("Running game. exe_dir = {s} ", .{exe_dir});

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const alloc_arena = arena.allocator();

    var buffer: [1024]u8 = undefined;
    const root_path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    _ = root_path;

    // set handlers
    _ = window.setKeyCallback(keyHandler);
    _ = window.setFramebufferSizeCallback(framebufferSizeHandler);
    _ = window.setCursorPosCallback(cursorPositionHandler);
    _ = window.setScrollCallback(scrollHandler);
    _ = window.setMouseButtonCallback(mouseHander);

    // Shaders
    const player_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/player_shader.vert", "games/angrybot/shaders/player_shader.frag");

    const player_emissive_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/player_shader.vert", "games/angrybot/shaders/texture_emissive_shader.frag");
    const wiggly_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/wiggly_shader.vert", "games/angrybot/shaders/player_shader.frag");
    const floor_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/basic_texture_shader.vert", "games/angrybot/shaders/floor_shader.frag");

    // bullets, muzzle flash, burn marks
    const instanced_texture_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/instanced_texture_shader.vert", "games/angrybot/shaders/basic_texture_shader.frag");
    const sprite_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/geom_shader2.vert", "games/angrybot/shaders/sprite_shader.frag");
    const basic_texture_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/basic_texture_shader.vert", "games/angrybot/shaders/basic_texture_shader.frag");

    // blur and scene
    const blur_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/basicer_shader.vert", "games/angrybot/shaders/blur_shader.frag");
    const scene_draw_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/basicer_shader.vert", "games/angrybot/shaders/texture_merge_shader.frag");

    // for debug
    const basicer_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/basicer_shader.vert", "games/angrybot/shaders/basicer_shader.frag");
    // const _depth_shader = try Shader.init(allocator, "games/angrybot/shaders/depth_shader.vert", "games/angrybot/shaders/depth_shader.frag");
    // const _debug_depth_shader = try Shader.init(allocator, "games/angrybot/shaders/debug_depth_quad.vert", "games/angrybot/shaders/debug_depth_quad.frag");

    defer player_shader.deinit();
    defer player_emissive_shader.deinit();
    defer wiggly_shader.deinit();
    defer floor_shader.deinit();
    defer instanced_texture_shader.deinit();
    defer sprite_shader.deinit();
    defer basic_texture_shader.deinit();
    defer blur_shader.deinit();
    defer scene_draw_shader.deinit();
    defer basicer_shader.deinit();

    log.info("games/angrybot/shaders loaded", .{});
    // --- Lighting ---

    const light_dir = vec3(-0.8, 0.0, -1.0).toNormalized();
    const player_light_dir = vec3(-1.0, -1.0, -1.0).toNormalized();
    const muzzle_point_light_color = vec3(1.0, 0.2, 0.0);

    const light_color = vec3(NON_BLUE * 0.406, NON_BLUE * 0.723, 1.0).mulScalar(LIGHT_FACTOR * 1.0);
    const ambient_color = vec3(NON_BLUE * 0.7, NON_BLUE * 0.7, 0.7).mulScalar(LIGHT_FACTOR * 0.10);

    const floor_light_color = vec3(FLOOR_NON_BLUE * 0.406, FLOOR_NON_BLUE * 0.723, 1.0).mulScalar(FLOOR_LIGHT_FACTOR * 1.0);
    const floor_ambient_color = vec3(FLOOR_NON_BLUE * 0.7, FLOOR_NON_BLUE * 0.7, 0.7).mulScalar(FLOOR_LIGHT_FACTOR * 0.50);

    const window_scale = window.getContentScale();

    var viewport_width = VIEW_PORT_WIDTH * window_scale[0];
    var viewport_height = VIEW_PORT_HEIGHT * window_scale[1];
    var scaled_width = viewport_width / window_scale[0];
    var scaled_height = viewport_height / window_scale[1];

    // -- Framebuffers ---

    const depth_map_fbo = fb.createDepthMapFbo();
    var emissions_fbo = fb.createEmissionFbo(viewport_width, viewport_height);
    var scene_fbo = fb.createSceneFbo(viewport_width, viewport_height);
    var horizontal_blur_fbo = fb.createHorizontalBlurFbo(viewport_width, viewport_height);
    var vertical_blur_fbo = fb.createVerticalBlurFbo(viewport_width, viewport_height);

    log.info("framebuffers loaded", .{});
    // --- quads ---

    const unit_square_quad = quads.createUnitSquareVao();
    // const _obnoxious_quad_vao = quads.create_obnoxious_quad_vao();
    const more_obnoxious_quad_vao = quads.createMoreObnoxiousQuadVao();

    log.info("quads loaded", .{});

    // --- Cameras ---

    const camera_follow_vec = vec3(-4.0, 4.3, 0.0);
    // const _camera_up = vec3(0.0, 1.0, 0.0);

    const game_camera = try Camera.init(
        alloc_arena,
        .{
            //.position = vec3(0.0, 20.0, 80.0),
            .position = vec3(0.0, 10.0, 40.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = VIEW_PORT_WIDTH,
            .scr_height = VIEW_PORT_HEIGHT,
        },
    );

    const floating_camera = try Camera.init(
        alloc_arena,
        .{
            .position = vec3(0.0, 10.0, 20.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = VIEW_PORT_WIDTH,
            .scr_height = VIEW_PORT_HEIGHT,
        },
    );

    const ortho_camera = try Camera.init(
        alloc_arena,
        .{
            .position = vec3(0.0, 1.0, 0.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = VIEW_PORT_WIDTH,
            .scr_height = VIEW_PORT_HEIGHT,
        },
    );

    defer game_camera.deinit();
    defer floating_camera.deinit();
    defer ortho_camera.deinit();

    const ortho_width = VIEW_PORT_WIDTH / 130.0;
    const ortho_height = VIEW_PORT_HEIGHT / 130.0;
    const aspect_ratio = VIEW_PORT_WIDTH / VIEW_PORT_HEIGHT;

    const game_projection = Mat4.perspectiveRhGl(math.degreesToRadians(game_camera.fov), aspect_ratio, 0.1, 100.0);
    const floating_projection = Mat4.perspectiveRhGl(math.degreesToRadians(floating_camera.fov), aspect_ratio, 0.1, 100.0);
    const orthographic_projection = Mat4.orthographicRhGl(-ortho_width, ortho_width, -ortho_height, ortho_height, 0.1, 100.0);

    // const game_projection = game_camera.getProjectionMatrixWithType(.Perspective);
    // const floating_projection = floating_camera.getProjectionMatrixWithType(.Perspective);
    // const orthographic_projection = ortho_camera.getProjectionMatrixWithType(.Orthographic);

    log.info("camers loaded", .{});

    // Models and systems (modern glTF system doesn't need global texture cache)
    var player = try Player.init(alloc_arena);
    log.info("player loaded - position: {any}", .{player.position});

    var enemy_system = try EnemySystem.init(alloc_arena);
    log.info("enemies loaded", .{});

    var muzzle_flash = try MuzzleFlash.init(&arena, unit_square_quad);
    log.info("muzzle_flash loaded", .{});

    var bullet_store = try BulletStore.init(&arena, unit_square_quad);
    log.info("bullet_store loaded", .{});

    var floor = try Floor.init(&arena);
    // log.info("floor loaded", .{});

    const burn_marks = try BurnMarks.init(&arena, unit_square_quad);

    log.info("models loaded", .{});

    const key_presses = EnumSet(glfw.Key).initEmpty();

    const clips = [2]world.ClipData{
        .{ .clip = .Explosion, .file = "angrybots_assets/Audio/Enemy_SFX/enemy_Spider_DestroyedExplosion.wav" },
        .{ .clip = .GunFire, .file = "angrybots_assets/Audio/Player_SFX/player_shooting.wav" },
    };

    var sound_engine = try SoundEngine(world.ClipName, world.ClipData).init(alloc_arena, &clips);
    defer sound_engine.deinit();

    // Initialize the world state
    state = State{
        .viewport_width = viewport_width,
        .viewport_height = viewport_height,
        .scaled_width = scaled_width,
        .scaled_height = scaled_height,
        .window_scale = window_scale,
        .game_camera = game_camera,
        .floating_camera = floating_camera,
        .ortho_camera = ortho_camera,
        .active_camera = CameraType.Game,
        .game_projection = game_projection,
        .floating_projection = floating_projection,
        .orthographic_projection = orthographic_projection,
        .player = player,
        .enemies = ArrayList(?Enemy).init(alloc_arena),
        .light_postion = vec3(1.2, 1.0, 2.0),
        .delta_time = 0.0,
        .frame_time = 0.0,
        .first_mouse = true,
        .last_x = VIEW_PORT_WIDTH / 2.0,
        .last_y = VIEW_PORT_HEIGHT / 2.0,
        .mouse_x = VIEW_PORT_WIDTH / 2.0,
        .mouse_y = VIEW_PORT_HEIGHT / 2.0,
        .burn_marks = burn_marks,
        .sound_engine = sound_engine,
        .key_presses = key_presses,
        .run = true,
    };

    log.info("state.viewport_width: {d}", .{state.viewport_width});
    log.info("state.viewport_height: {d}", .{state.viewport_height});
    log.info("state.mouse_x: {d}", .{state.mouse_x});
    log.info("state.mouse_y: {d}", .{state.mouse_y});

    // note: defer occurs in reverse order
    defer player.deinit();
    defer enemy_system.deinit();
    defer state.enemies.deinit();

    // Set fixed shader uniforms

    const shadow_texture_unit = 10;

    player_shader.useShader();
    player_shader.setVec3("directionLight.dir", &player_light_dir);
    player_shader.setVec3("directionLight.color", &light_color);
    player_shader.setVec3("ambient", &ambient_color);

    player_shader.setInt("shadow_map", shadow_texture_unit);
    player_shader.setTextureUnit(shadow_texture_unit, depth_map_fbo.texture_id);

    floor_shader.useShader();
    floor_shader.setVec3("directionLight.dir", &light_dir);
    floor_shader.setVec3("directionLight.color", &floor_light_color);
    floor_shader.setVec3("ambient", &floor_ambient_color);

    floor_shader.setInt("shadow_map", shadow_texture_unit);
    floor_shader.setTextureUnit(shadow_texture_unit, depth_map_fbo.texture_id);

    wiggly_shader.useShader();
    wiggly_shader.setVec3("directionLight.dir", &player_light_dir);
    wiggly_shader.setVec3("directionLight.color", &light_color);
    wiggly_shader.setVec3("ambient", &ambient_color);

    log.info("games/angrybot/shaders initilized", .{});
    // --------------------------------

    const use_framebuffers = true;

    var aim_theta: f32 = 0.0;
    var quad_vao: gl.Uint = 0;

    const emission_texture_unit = 0;
    const horizontal_texture_unit = 1;
    const vertical_texture_unit = 2;
    const scene_texture_unit = 3;

    // --- event loop
    state.frame_time = @floatCast(glfw.getTime());
    var frame_counter = core.FrameCounter.new();

    log.info("Starting game loop!", .{});

    while (!window.shouldClose()) {
        glfw.pollEvents();

        const currentFrame: f32 = @floatCast(glfw.getTime());
        if (state.run) {
            state.delta_time = currentFrame - state.frame_time;
        } else {
            state.delta_time = 0.0;
        }
        state.frame_time = currentFrame;

        // log.info("currentFrame = {d} frame_time = {d}", .{currentFrame, state.last_frame});

        frame_counter.update();

        gl.clearColor(0.0, 0.82, 0.25, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.enable(gl.DEPTH_TEST);

        if (viewport_width != state.viewport_width or viewport_height != state.viewport_height) {
            viewport_width = state.viewport_width;
            viewport_height = state.viewport_height;
            scaled_width = state.scaled_width;
            scaled_height = state.scaled_height;

            if (use_framebuffers) {
                emissions_fbo = fb.createEmissionFbo(viewport_width, viewport_height);
                scene_fbo = fb.createSceneFbo(viewport_width, viewport_height);
                horizontal_blur_fbo = fb.createHorizontalBlurFbo(viewport_width, viewport_height);
                vertical_blur_fbo = fb.createVerticalBlurFbo(viewport_width, viewport_height);
            }
            // log.info(
            //     "view port size: {d}, {d}  scaled size: {d}, {d}",
            //     .{ viewport_width, viewport_height, scaled_width, scaled_height },
            // );
        }

        state.game_camera.movement.position = player.position.add(&camera_follow_vec);
        const game_view = Mat4.lookAtRhGl(
            &state.game_camera.movement.position,
            &player.position,
            &state.game_camera.movement.up,
        );

        var pv: PV = undefined;
        switch (state.active_camera) {
            CameraType.Game => {
                pv = .{ .projection = state.game_projection, .view = game_view };
            },
            CameraType.Floating => {
                const view = Mat4.lookAtRhGl(
                    &state.floating_camera.movement.position,
                    &player.position,
                    &state.floating_camera.movement.up,
                );
                pv = .{ .projection = state.floating_projection, .view = view };
            },
            CameraType.TopDown => {
                const view = Mat4.lookAtRhGl(
                    &vec3(player.position.x, 1.0, player.position.z),
                    //&player.position.add(&vec3(0.0, 1.0, 0.0)),
                    &player.position,
                    &vec3(0.0, 0.0, -1.0),
                );
                pv = .{ .projection = state.orthographic_projection, .view = view };
            },
            CameraType.Side => {
                const view = Mat4.lookAtRhGl(
                    &player.position.add(&vec3(0.0, 0.0, -3.0)),
                    &player.position,
                    &vec3(0.0, 1.0, 0.0),
                );
                pv = .{ .projection = state.orthographic_projection, .view = view };
            },
        }

        const projection_view = pv.projection.mulMat4(&pv.view);

        // log.info("camera.position = {any}\ncamera.up = {any}\ncamera.front = {any}\nprojection = {any}\nview = {any}\nprojection_view = {any}\n",
        //     .{
        //         state.game_camera.position,
        //         state.game_camera.front,
        //         state.game_camera.up,
        //         pv.projection,
        //         pv.view,
        //         projection_view,
        //     });

        var dx: f32 = 0.0;
        var dz: f32 = 0.0;

        if (player.is_alive) {
            const world_ray = math.getWorldRayFromMouse(
                state.scaled_width,
                state.scaled_height,
                &state.game_projection,
                &game_view,
                state.mouse_x + 0.0001,
                state.mouse_y,
            );

            const xz_plane_point = vec3(0.0, 0.0, 0.0);
            const xz_plane_normal = vec3(0.0, 1.0, 0.0);

            const world_point = math.getRayPlaneIntersection(
                &state.game_camera.movement.position,
                &world_ray,
                &xz_plane_point,
                &xz_plane_normal,
            );

            if (world_point) |point| {
                dx = point.x - player.position.x;
                dz = point.z - player.position.z;

                if (dz != 0.0) {
                    aim_theta = math.atan(dx / dz);
                }

                if (dz < 0.0) {
                    aim_theta = aim_theta + math.pi;
                }

                if (@abs(state.mouse_x) < 0.005 and @abs(state.mouse_y) < 0.005) {
                    aim_theta = 0.0;
                }
            }
        }

        const aim_rot = Mat4.fromAxisAngle(&vec3(0.0, 1.0, 0.0), aim_theta);

        var player_scale = Vec3.splat(world.PLAYER_MODEL_SCALE);
        var scale_mat4 = Mat4.fromScale(&player_scale);
        var player_transform = Mat4.fromTranslation(&player.position);

        // log.info("player_transfrom translation = {any}\ninverse = {any}", .{player_transform, Mat4.getInverse(&player_transform)});

        player_transform = player_transform.mulMat4(&scale_mat4);
        player_transform = player_transform.mulMat4(&aim_rot);

        // log.info("player.position = {any}\nplayer_scale = {any}\nscale_mat4 = {any}\nplayer_transform = {any}\naim_rot = {any}\n", .{
        //     player.position,
        //     player_scale,
        //     scale_mat4,
        //     player_transform,
        //     aim_rot
        // });

        const muzzle_transform = player.getMuzzlePosition(&player_transform);

        if (player.is_alive and player.is_trying_to_fire and (player.last_fire_time + world.FIRE_INTERVAL) < state.frame_time) {
            player.last_fire_time = state.frame_time;
            if (try bullet_store.createBullets(aim_theta, &muzzle_transform)) {
                try muzzle_flash.addFlash();
                state.sound_engine.playSound(.GunFire);
            }
        }

        // log.info("updating muzzle_flash", .{});
        muzzle_flash.update(state.delta_time);

        // log.info("updating bullet_store", .{});
        try bullet_store.updateBullets(&state);

        if (player.is_alive) {
            // log.info("updating enemies", .{});
            try enemy_system.update(&state);
            enemy_system.chasePlayer(&state);
        }

        // Update Player
        // log.info("updating player", .{});
        try player.update(&state, aim_theta);

        var use_point_light = false;
        var muzzle_world_position = Vec3.default();

        if (muzzle_flash.muzzle_flash_sprites_age.items.len != 0) {
            const min_age = muzzle_flash.getMinAge();
            const muzzle_world_position_vec4 = muzzle_transform.mulVec4(&vec4(0.0, 0.0, 0.0, 1.0));

            muzzle_world_position = vec3(
                muzzle_world_position_vec4.x / muzzle_world_position_vec4.w,
                muzzle_world_position_vec4.y / muzzle_world_position_vec4.w,
                muzzle_world_position_vec4.z / muzzle_world_position_vec4.w,
            );

            use_point_light = min_age < 0.03;
        }

        const near_plane: f32 = 1.0;
        const far_plane: f32 = 50.0;
        const ortho_size: f32 = 10.0;

        const light_projection = Mat4.orthographicRhGl(-ortho_size, ortho_size, -ortho_size, ortho_size, near_plane, far_plane);
        const light_view = Mat4.lookAtRhGl(&player.position.sub(&player_light_dir.mulScalar(20)), &player.position, &vec3(0.0, 1.0, 0.0));
        const light_space_matrix = light_projection.mulMat4(&light_view);

        // log.info("light_projection = {any}\nplayer.position = {any}\neye = {any}\nlight_view = {any}\nlight_space_matrix = {any}", .{
        //     light_projection,
        //     player.position,
        //     player.position.sub(&player_light_dir.mulScalar(20)),
        //     light_view,
        //     light_space_matrix,
        // });

        // log.info("updating shaders", .{});
        player_shader.useShader();

        player_shader.setMat4("projectionView", &projection_view);
        player_shader.setMat4("model", &player_transform);
        player_shader.setMat4("aimRot", &aim_rot);
        player_shader.setVec3("viewPos", &state.game_camera.movement.position);
        player_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        player_shader.setBool("usePointLight", use_point_light);
        player_shader.setVec3("pointLight.color", &muzzle_point_light_color);
        player_shader.setVec3("pointLight.worldPos", &muzzle_world_position);

        floor_shader.useShader();
        floor_shader.setVec3("viewPos", &state.game_camera.movement.position);
        floor_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        floor_shader.setBool("usePointLight", use_point_light);
        floor_shader.setVec3("pointLight.color", &muzzle_point_light_color);
        floor_shader.setVec3("pointLight.worldPos", &muzzle_world_position);

        // shadows start - render to depth fbo
        gl.bindFramebuffer(gl.FRAMEBUFFER, depth_map_fbo.framebuffer_id);
        gl.viewport(0, 0, fb.SHADOW_WIDTH, fb.SHADOW_HEIGHT);
        gl.clear(gl.DEPTH_BUFFER_BIT);

        player_shader.useShader();
        player_shader.setBool("depth_mode", true); // was true
        player_shader.setBool("useLight", true);

        // log.info("rendering player", .{});
        player.render(player_shader);

        wiggly_shader.useShader();
        wiggly_shader.setMat4("projectionView", &projection_view);
        wiggly_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        wiggly_shader.setBool("depth_mode", true);

        // log.info("rendering enemies", .{});
        enemy_system.drawEnemies(wiggly_shader, &state);

        // shadows end

        if (use_framebuffers) {
            // render to emission buffer

            gl.bindFramebuffer(gl.FRAMEBUFFER, emissions_fbo.framebuffer_id);
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
            gl.clearColor(0.0, 0.0, 0.0, 0.0);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

            player_emissive_shader.useShader();
            player_emissive_shader.setMat4("projectionView", &projection_view);
            player_emissive_shader.setMat4("model", &player_transform);

            // log.info("rendering player with emissive shader", .{});
            player.render(player_emissive_shader);

            // doesn't seem to do anything
            // {
            //     unsafe {
            //         gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE);
            //     }
            //
            //     floor_shader.use_shader();
            //     floor_shader.setBool("usePointLight", true);
            //     floor_shader.setBool("useLight", true);
            //     floor_shader.setBool("useSpec", true);
            //
            //     // floor.draw(&floor_shader, &projection_view);
            //
            //     unsafe {
            //         gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE);
            //     }
            // }

            // log.info("rendering bullet_store ", .{});
            bullet_store.drawBullets(instanced_texture_shader, &projection_view);

            const debug_emission = false;
            if (debug_emission) {
                const texture_unit = 0;
                gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
                gl.viewport(0, 0, viewport_width, viewport_height);
                gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

                gl.activeTexture(gl.TEXTURE0 + texture_unit);
                gl.bindTexture(gl.TEXTURE_2D, emissions_fbo.texture_id);

                basicer_shader.useShader();
                basicer_shader.setBool("greyscale", false);
                basicer_shader.setInt("tex", texture_unit);

                // log.info("rendering quads ", .{});
                quads.renderQuad(&quad_vao);

                window.swap_buffers();
                continue;
            }
        }

        // const debug_depth = false;
        // if debug_depth {
        //     unsafe {
        //         gl.activeTexture(gl.TEXTURE0);
        //         gl.bindTexture(gl.TEXTURE_2D, depth_map_fbo.texture_id);
        //         gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        //     }
        //     debug_depth_shader.use_shader();
        //     debug_depth_shader.set_float("near_plane", near_plane);
        //     debug_depth_shader.set_float("far_plane", far_plane);
        //     render_quad(&quad_vao);
        // }

        // render to scene buffer for base texture
        if (use_framebuffers) {
            gl.bindFramebuffer(gl.FRAMEBUFFER, scene_fbo.framebuffer_id);
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
            gl.clearColor(0.0, 0.02, 0.25, 1.0);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        } else {
            gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
        }

        floor_shader.useShader();
        floor_shader.setBool("useLight", true);
        floor_shader.setBool("useSpec", true);

        // log.info("rendering floor", .{});
        floor.draw(floor_shader, &projection_view);

        player_shader.useShader();
        player_shader.setBool("useLight", true);
        player_shader.setBool("useEmissive", true);
        player_shader.setBool("depth_mode", false);

        // log.info("rendering player", .{});
        player.render(player_shader);

        muzzle_flash.draw(sprite_shader, &projection_view, &muzzle_transform);

        wiggly_shader.useShader();
        wiggly_shader.setBool("useLight", true);
        wiggly_shader.setBool("useEmissive", false);
        wiggly_shader.setBool("depth_mode", false);

        // log.info("rendering enemies", .{});
        enemy_system.drawEnemies(wiggly_shader, &state);

        // log.debug("rendering burn_marks", .{});
        state.burn_marks.drawMarks(basic_texture_shader, &projection_view, state.delta_time);

        // log.info("rendering bullet_impacts", .{});
        bullet_store.drawBulletImpacts(sprite_shader, &projection_view);

        if (!use_framebuffers) {
            bullet_store.drawBullets(instanced_texture_shader, &projection_view);
        }

        if (use_framebuffers) {
            // generated blur and combine with emission and scene for final draw to framebuffer 0
            // gl.Disable(gl.DEPTH_TEST);

            // view port for blur effect
            gl.viewport(0, 0, @intFromFloat(viewport_width / BLUR_SCALE), @intFromFloat(viewport_height / BLUR_SCALE));

            // Draw horizontal blur
            gl.bindFramebuffer(gl.FRAMEBUFFER, horizontal_blur_fbo.framebuffer_id);
            gl.bindVertexArray(more_obnoxious_quad_vao);

            gl.activeTexture(gl.TEXTURE0 + emission_texture_unit);
            gl.bindTexture(gl.TEXTURE_2D, emissions_fbo.texture_id);

            blur_shader.useShader();
            blur_shader.setInt("image", emission_texture_unit);
            blur_shader.setBool("horizontal", true);

            gl.drawArrays(gl.TRIANGLES, 0, 6);

            // Draw vertical blur
            gl.bindFramebuffer(gl.FRAMEBUFFER, vertical_blur_fbo.framebuffer_id);
            gl.bindVertexArray(more_obnoxious_quad_vao);

            gl.activeTexture(gl.TEXTURE0 + horizontal_texture_unit);
            gl.bindTexture(gl.TEXTURE_2D, horizontal_blur_fbo.texture_id);

            blur_shader.useShader();
            blur_shader.setInt("image", horizontal_texture_unit);
            blur_shader.setBool("horizontal", false);

            gl.drawArrays(gl.TRIANGLES, 0, 6);

            // view port for final draw combining everything
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));

            gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            gl.bindVertexArray(more_obnoxious_quad_vao);

            gl.activeTexture(gl.TEXTURE0 + vertical_texture_unit);
            gl.bindTexture(gl.TEXTURE_2D, vertical_blur_fbo.texture_id);

            gl.activeTexture(gl.TEXTURE0 + emission_texture_unit);
            gl.bindTexture(gl.TEXTURE_2D, emissions_fbo.texture_id);

            gl.activeTexture(gl.TEXTURE0 + scene_texture_unit);
            gl.bindTexture(gl.TEXTURE_2D, scene_fbo.texture_id);

            scene_draw_shader.useShader();
            scene_draw_shader.setInt("base_texture", scene_texture_unit);
            scene_draw_shader.setInt("emission_texture", vertical_texture_unit);
            scene_draw_shader.setInt("bright_texture", emission_texture_unit);

            gl.drawArrays(gl.TRIANGLES, 0, 6);

            // gl.Enable(gl.DEPTH_TEST);

            const debug_blur = false;
            if (debug_blur) {
                const texture_unit = 0;
                gl.bindFramebuffer(gl.FRAMEBUFFER, 0);

                gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
                gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

                gl.activeTexture(gl.TEXTURE0 + texture_unit);
                gl.bindTexture(gl.TEXTURE_2D, scene_fbo.texture_id);

                basicer_shader.useShader();
                basicer_shader.setBool("greyscale", false);
                basicer_shader.setInt("tex", texture_unit);

                quads.renderQuad(&quad_vao);

                window.swap_buffers();
                continue;
            }
        }

        window.swapBuffers();
    }

    log.info("\nRun completed.\n", .{});
    // test_ray();
}

fn keyHandler(window: *glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    _ = scancode;
    if (key == .escape) {
        window.setShouldClose(true);
    }
    if (mods.shift) {
        switch (key) {
            .w => state.game_camera.movement.processMovement(.Forward, state.delta_time),
            .s => state.game_camera.movement.processMovement(.Backward, state.delta_time),
            .a => state.game_camera.movement.processMovement(.Left, state.delta_time),
            .d => state.game_camera.movement.processMovement(.Right, state.delta_time),
            else => {},
        }
    } else {
        switch (key) {
            .t => if (action == glfw.Action.press) {
                log.info("time: {d}", .{state.delta_time});
            },
            .w => handleKeyPress(action, key),
            .s => handleKeyPress(action, key),
            .a => handleKeyPress(action, key),
            .d => handleKeyPress(action, key),
            .one => state.active_camera = CameraType.Game,
            .two => state.active_camera = CameraType.Floating,
            .three => state.active_camera = CameraType.TopDown,
            .four => state.active_camera = CameraType.Side,
            .space => if (action == glfw.Action.press) {
                state.run = !state.run;
            },
            else => {},
        }
    }
}

fn framebufferSizeHandler(window: *glfw.Window, width: i32, height: i32) callconv(.C) void {
    _ = window;
    gl.viewport(0, 0, width, height);
    setViewPort(width, height);
}

fn setViewPort(w: i32, h: i32) void {
    const width: f32 = @floatFromInt(w);
    const height: f32 = @floatFromInt(h);

    state.viewport_width = width;
    state.viewport_height = height;
    state.scaled_width = width / state.window_scale[0];
    state.scaled_height = height / state.window_scale[1];

    const ortho_width = (state.viewport_width / 500);
    const ortho_height = (state.viewport_height / 500);
    const aspect_ratio = (state.viewport_width / state.viewport_height);

    state.game_projection = Mat4.perspectiveRhGl(math.degreesToRadians(state.game_camera.fov), aspect_ratio, 0.1, 100.0);
    state.floating_projection = Mat4.perspectiveRhGl(math.degreesToRadians(state.floating_camera.fov), aspect_ratio, 0.1, 100.0);
    state.orthographic_projection = Mat4.orthographicRhGl(-ortho_width, ortho_width, -ortho_height, ortho_height, 0.1, 100.0);
}

fn cursorPositionHandler(window: *glfw.Window, xposIn: f64, yposIn: f64) callconv(.C) void {
    _ = window;
    state.mouse_x = math.clamp(@as(f32, @floatCast(xposIn)), 0, state.viewport_width);
    state.mouse_y = math.clamp(@as(f32, @floatCast(yposIn)), 0, state.viewport_height);
}

fn mouseHander(window: *glfw.Window, button: glfw.MouseButton, action: glfw.Action, mods: glfw.Mods) callconv(.C) void {
    _ = window;
    _ = mods;
    switch (button) {
        .left => {
            // log.info("left mouse button action = {any}", .{action});
            switch (action) {
                .press => state.player.is_trying_to_fire = true,
                .release => state.player.is_trying_to_fire = false,
                else => {},
            }
        },
        else => {},
    }
}

fn scrollHandler(window: *Window, xoffset: f64, yoffset: f64) callconv(.C) void {
    _ = window;
    _ = xoffset;
    state.game_camera.adjustFov(@floatCast(yoffset));
    const aspect_ratio = (state.viewport_width / state.viewport_height);
    state.game_projection = Mat4.perspectiveRhGl(math.degreesToRadians(state.game_camera.fov), aspect_ratio, 0.1, 100.0);
    state.floating_projection = Mat4.perspectiveRhGl(math.degreesToRadians(state.floating_camera.fov), aspect_ratio, 0.1, 100.0);
}

fn handleKeyPress(action: glfw.Action, key: glfw.Key) void {
    switch (action) {
        .release => state.key_presses.remove(key),
        .press => state.key_presses.insert(key),
        else => {},
    }

    if (state.player.is_alive) {
        const player_speed = state.player.speed;
        var direction_vec = Vec3.splat(0.0);

        var iterator = state.key_presses.iterator();
        while (iterator.next()) |k| {
            switch (k) {
                glfw.Key.a => direction_vec.addTo(&vec3(0.0, 0.0, -1.0)),
                glfw.Key.d => direction_vec.addTo(&vec3(0.0, 0.0, 1.0)),
                glfw.Key.s => direction_vec.addTo(&vec3(-1.0, 0.0, 0.0)),
                glfw.Key.w => direction_vec.addTo(&vec3(1.0, 0.0, 0.0)),
                else => {},
            }
        }

        if (direction_vec.lengthSquared() > 0.01) {
            state.player.position.addTo(&direction_vec.toNormalized().mulScalar(player_speed * state.delta_time));
        }
        state.player.direction = vec2(direction_vec.x, direction_vec.z);

        // log.info("key presses: {any}" , .{state.key_presses});
        // log.info("direction: {any}  player.direction: {any}  delta_time: {any}", .{direction_vec, state.player.direction, state.frame_time});
    }
}

fn testRay() void {
    const mouse_x = 1117.3203;
    const mouse_y = 323.6797;
    const width = 1500.0;
    const height = 1000.0;

    const view_matrix = Mat4.fromColumns(
        vec4(0.345086, 0.64576554, -0.68110394, 0.0),
        vec4(0.3210102, 0.6007121, 0.7321868, 0.0),
        vec4(0.8819683, -0.47130874, -0.0, 0.0),
        vec4(1.1920929e-7, -0.0, -5.872819, 1.0),
    );

    const projection = Mat4.fromColumns(
        vec4(1.6094756, 0.0, 0.0, 0.0),
        vec4(0.0, 2.4142134, 0.0, 0.0),
        vec4(0.0, 0.0, -1.002002, -1.0),
        vec4(0.0, 0.0, -0.2002002, 0.0),
    );

    const ray = math.get_world_ray_from_mouse(
        width,
        height,
        &projection,
        &view_matrix,
        mouse_x,
        mouse_y,
    );

    const xz_plane_point = vec3(0.0, 0.0, 0.0);
    const xz_plane_normal = vec3(0.0, 1.0, 0.0);

    const world_point = math.ray_plane_intersection(
        &vec3(0.0, 20.0, 80.0),
        &ray,
        &xz_plane_point,
        &xz_plane_normal,
    ).?;

    const player_position_x: f32 = 0.0;
    const player_position_z: f32 = 0.0;

    const dx = world_point.x - player_position_x;
    const dz = world_point.z - player_position_z;

    var aim_theta = math.atan(dx / dz);

    if (dz < 0.0) {
        aim_theta = aim_theta + math.pi;
    }

    if (@abs(state.mouse_x) < 0.005 and @abs(state.mouse_y) < 0.005) {
        aim_theta = 0.0;
    }

    const degrees = math.radiansToDegrees(aim_theta);

    log.info("ray = {any}\nworld_point = {any}\naim_theta = {d}\ndegrees = {d}\n", .{ ray, world_point, aim_theta, degrees });
}
