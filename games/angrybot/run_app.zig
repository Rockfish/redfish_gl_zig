const std = @import("std");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const core = @import("core");
const math = @import("math");
const containers = @import("containers");
const world = @import("state.zig");

const ManagedArrayList = containers.ManagedArrayList;
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

const log = std.log.scoped(.Run_App);

const Window = glfw.Window;

const VIEW_PORT_WIDTH: f32 = 1500.0;
const VIEW_PORT_HEIGHT: f32 = 1000.0;

// Lighting
const LIGHT_FACTOR: f32 = 0.8;
const NON_BLUE: f32 = 0.9;
const BLUR_SCALE: i32 = 2;
const FLOOR_LIGHT_FACTOR: f32 = 0.35;
const FLOOR_NON_BLUE: f32 = 0.7;

var state: State = undefined;

// Global framebuffers
var depth_map_fbo: fb.FrameBuffer = undefined;
var emissions_fbo: fb.FrameBuffer = undefined;
var scene_fbo: fb.FrameBuffer = undefined;
var horizontal_blur_fbo: fb.FrameBuffer = undefined;
var vertical_blur_fbo: fb.FrameBuffer = undefined;

pub fn run(window: *glfw.Window) !void {
    var buf: [512]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&buf);
    // const cwd = try std.os.getFdPath(&buf);
    log.info("Running game. exe_dir = {s} ", .{exe_dir});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    var buffer: [1024]u8 = undefined;
    const root_path = std.fs.selfExeDirPath(buffer[0..]) catch ".";
    _ = root_path;

    world.initStateHandlers(window, &state);

    // Shaders
    const player_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/player_shader.vert",
        "games/angrybot/shaders/player_shader.frag",
    );
    const player_emissive_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/player_shader.vert",
        "games/angrybot/shaders/texture_emissive_shader.frag",
    );

    const enemy_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/wiggly_shader.vert",
        "games/angrybot/shaders/player_shader.frag",
    );

    const floor_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/basic_texture_shader.vert",
        "games/angrybot/shaders/floor_shader.frag",
    );

    // bullets, muzzle flash, burn marks - using matrix-based instanced shader
    const instanced_matrix_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/instanced_quat.vert",
        "games/angrybot/shaders/basic_texture_shader.frag",
    );
    const sprite_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/geom_shader2.vert",
        "games/angrybot/shaders/sprite_shader.frag",
    );
    const basic_texture_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/basic_texture_shader.vert",
        "games/angrybot/shaders/basic_texture_shader.frag",
    );

    // blur and scene
    const blur_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/basicer_shader.vert",
        "games/angrybot/shaders/blur_shader.frag",
    );
    const scene_draw_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/basicer_shader.vert",
        "games/angrybot/shaders/texture_merge_shader.frag",
    );

    // for debug
    const basicer_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/basicer_shader.vert",
        "games/angrybot/shaders/basicer_shader.frag",
    );
    // const _depth_shader = try Shader.init(alloc_arena, "games/angrybot/shaders/depth_shader.vert", "games/angrybot/shaders/depth_shader.frag");
    const _debug_depth_shader = try Shader.init(
        allocator,
        "games/angrybot/shaders/debug_depth_quad.vert",
        "games/angrybot/shaders/debug_depth_quad.frag",
    );
    _ = _debug_depth_shader;

    defer player_shader.deinit();
    defer player_emissive_shader.deinit();
    defer enemy_shader.deinit();
    defer floor_shader.deinit();
    defer instanced_matrix_shader.deinit();
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

    framebufferCreate(viewport_width, viewport_height);

    log.info("framebuffers loaded", .{});
    // --- quads ---

    const unit_square_quad = quads.createUnitSquareVao();
    // const _obnoxious_quad_vao = quads.create_obnoxious_quad_vao();
    const more_obnoxious_quad_vao = quads.createMoreObnoxiousQuadVao();

    log.info("quads loaded", .{});

    // --- Cameras ---

    // const camera_follow_vec = vec3(-4.0, 4.3, 0.0); //original

    // const _camera_up = vec3(0.0, 1.0, 0.0);

    const game_camera = try Camera.init(
        allocator,
        .{
            //.position = vec3(0.0, 20.0, 80.0),
            .position = vec3(4.0, 10.0, 30.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = VIEW_PORT_WIDTH,
            .scr_height = VIEW_PORT_HEIGHT,
        },
    );

    const floating_camera = try Camera.init(
        allocator,
        .{
            .position = vec3(0.0, 10.0, 20.0),
            .target = vec3(0.0, 0.0, 0.0),
            .scr_width = VIEW_PORT_WIDTH,
            .scr_height = VIEW_PORT_HEIGHT,
        },
    );

    const ortho_camera = try Camera.init(
        allocator,
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

    // const game_projection = game_camera.getProjectionMatrixWithType(.Perspective);
    // const floating_projection = floating_camera.getProjectionMatrixWithType(.Perspective);
    // const orthographic_projection = ortho_camera.getProjectionMatrixWithType(.Orthographic);

    log.info("camers loaded", .{});

    // Models and systems (modern glTF system doesn't need global texture cache)
    var player = try Player.init(allocator);
    var enemy_system = try EnemySystem.init(allocator);
    var muzzle_flash = try MuzzleFlash.init(allocator, unit_square_quad);
    var bullet_store = try BulletStore.init(allocator, unit_square_quad);
    var floor = try Floor.init(allocator);
    const burn_marks = try BurnMarks.init(allocator, unit_square_quad);

    log.info("models loaded", .{});

    const clips = [2]world.ClipData{
        .{ .clip = .Explosion, .file = "assets/angrybots_assets/Audio/Enemy_SFX/enemy_Spider_DestroyedExplosion.wav" },
        .{ .clip = .GunFire, .file = "assets/angrybots_assets/Audio/Player_SFX/player_shooting.wav" },
    };

    var sound_engine = try SoundEngine(world.ClipName, world.ClipData).init(allocator, &clips);
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
        .active_camera = game_camera,
        // .game_projection = game_projection,
        // .floating_projection = floating_projection,
        // .orthographic_projection = orthographic_projection,
        // .projection_view = undefined,
        .player = player,
        .enemies = ManagedArrayList(?Enemy).init(allocator),
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
        .run = true,
        .input = .{
            .first_mouse = true,
            .mouse_x = scaled_width / 2.0,
            .mouse_y = scaled_height / 2.0,
            .key_presses = EnumSet(glfw.Key).initEmpty(),
        },
    };

    log.info("state.viewport_width: {d}", .{state.viewport_width});
    log.info("state.viewport_height: {d}", .{state.viewport_height});
    log.info("state.mouse_x: {d}", .{state.mouse_x});
    log.info("state.mouse_y: {d}", .{state.mouse_y});

    // note: defer occurs in reverse order
    defer player.deinit();
    defer enemy_system.deinit();
    defer state.enemies.deinit();

    // Set constant shader uniforms

    player_shader.useShader();
    player_shader.setVec3("directionLight.dir", player_light_dir);
    player_shader.setVec3("directionLight.color", light_color);
    player_shader.setVec3("ambient", ambient_color);

    // player_shader.bindTextureAuto("shadow_map", depth_map_fbo.texture_id);

    floor_shader.useShader();
    floor_shader.setVec3("directionLight.dir", light_dir);
    floor_shader.setVec3("directionLight.color", floor_light_color);
    floor_shader.setVec3("ambient", floor_ambient_color);

    // floor_shader.bindTextureAuto("shadow_map", depth_map_fbo.texture_id);

    enemy_shader.useShader();
    enemy_shader.setVec3("directionLight.dir", player_light_dir);
    enemy_shader.setVec3("directionLight.color", light_color);
    enemy_shader.setVec3("ambient", ambient_color);

    log.info("games/angrybot/shaders initilized", .{});
    // --------------------------------

    const use_framebuffers = false;

    var aim_angle: f32 = 0.0;
    // var quad_vao: gl.Uint = 0;

    // --- event loop
    state.frame_time = @floatCast(glfw.getTime());
    var frame_counter = core.FrameCounter.new();

    log.info("Starting game loop!", .{});

    while (!window.shouldClose()) {
        glfw.pollEvents();

        frame_counter.update();

        const currentFrame: f32 = @floatCast(glfw.getTime());
        if (state.run) {
            state.delta_time = currentFrame - state.frame_time;
        } else {
            state.delta_time = 0.0;
        }
        state.frame_time = currentFrame;

        world.processInput();

        // gl.clearColor(0.0, 0.82, 0.25, 1.0);
        gl.clearColor(0.1, 0.1, 0.1, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.enable(gl.DEPTH_TEST);

        if (viewport_width != state.viewport_width or viewport_height != state.viewport_height) {
            viewport_width = state.viewport_width;
            viewport_height = state.viewport_height;
            scaled_width = state.scaled_width;
            scaled_height = state.scaled_height;

            framebufferUpdate(viewport_width, viewport_height, use_framebuffers);
        }

        state.game_camera.movement.target = state.player.position;
        state.active_camera.movement.target = state.player.position;
        // world.updateCameras();
        //
        // const game_view = Mat4.lookAtRhGl(
        // &state.game_camera.movement.position,
        // &state.player.position,
        // &state.game_camera.movement.up,
        // );

        aim_angle = world.getMousePointAngle(&state.game_camera.getView(), &state.player.position);
        const aim_rotation_matrix = Mat4.fromAxisAngle(vec3(0.0, 1.0, 0.0), aim_angle);

        const player_scale = Vec3.splat(world.PLAYER_MODEL_SCALE);
        var scale_mat4 = Mat4.fromScale(player_scale);

        var player_transform = Mat4.fromTranslation(player.position);
        player_transform = player_transform.mulMat4(&scale_mat4);
        player_transform = player_transform.mulMat4(&aim_rotation_matrix);

        const muzzle_transform = player.getMuzzlePosition(&player_transform);

        if (player.is_alive and player.is_trying_to_fire and (player.last_fire_time + world.FIRE_INTERVAL) < state.frame_time) {
            player.last_fire_time = state.frame_time;
            if (try bullet_store.createBullets(aim_angle, &muzzle_transform)) {
                try muzzle_flash.addFlash();
                state.sound_engine.playSound(.GunFire);
            }
        }

        muzzle_flash.update(state.delta_time);

        try bullet_store.updateBullets(&state);

        if (player.is_alive) {
            try enemy_system.update(&state);
            enemy_system.chasePlayer(&state);
        }

        try player.update(&state, aim_angle);

        var use_point_light = false;
        var muzzle_world_position = Vec3.Zero;

        if (muzzle_flash.muzzle_flash_sprites_age.list.items.len != 0) {
            const min_age = muzzle_flash.getMinAge();
            const muzzle_world_position_vec4 = muzzle_transform.mulVec4(vec4(0.0, 0.0, 0.0, 1.0));

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
        const light_view = Mat4.lookAtRhGl(player.position.sub(player_light_dir.mulScalar(20)), player.position, Vec3.World_Up);
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

        player_shader.setMat4("projectionView", &state.active_camera.getProjectionView());
        player_shader.setMat4("model", &player_transform);
        player_shader.setMat4("aimRot", &aim_rotation_matrix);
        player_shader.setVec3("viewPos", state.game_camera.movement.transform.translation);
        player_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        player_shader.setBool("usePointLight", use_point_light);
        player_shader.setVec3("pointLight.color", muzzle_point_light_color);
        player_shader.setVec3("pointLight.worldPos", muzzle_world_position);

        floor_shader.useShader();
        floor_shader.setVec3("viewPos", state.game_camera.movement.transform.translation);
        floor_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        floor_shader.setBool("usePointLight", use_point_light);
        floor_shader.setVec3("pointLight.color", muzzle_point_light_color);
        floor_shader.setVec3("pointLight.worldPos", muzzle_world_position);

        //
        // shadows start - write to depth map fbo
        //

        gl.bindFramebuffer(gl.FRAMEBUFFER, depth_map_fbo.framebuffer_id);
        gl.viewport(0, 0, fb.SHADOW_WIDTH, fb.SHADOW_HEIGHT);
        gl.clear(gl.DEPTH_BUFFER_BIT);

        player_shader.useShader();
        player_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        player_shader.setMat4("projectionView", &state.active_camera.getProjectionView());
        player_shader.setBool("depth_mode", true);
        player_shader.setBool("useLight", false);

        player.draw(player_shader);

        enemy_shader.useShader();
        enemy_shader.setMat4("projectionView", &state.active_camera.getProjectionView());
        enemy_shader.setMat4("lightSpaceMatrix", &light_space_matrix);
        enemy_shader.setBool("depth_mode", true);

        enemy_system.drawEnemies(enemy_shader, &state);

        //
        // shadows end
        //

        if (use_framebuffers) {
            // draw to emission buffer

            gl.bindFramebuffer(gl.FRAMEBUFFER, emissions_fbo.framebuffer_id);
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
            gl.clearColor(0.0, 0.0, 0.0, 0.0);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

            player_emissive_shader.useShader();
            player_emissive_shader.setMat4("projectionView", &state.active_camera.getProjectionView());
            player_emissive_shader.setMat4("model", &player_transform);

            // log.info("drawing player with emissive shader", .{});
            // player_shader.bindTextureAuto("shadow_map", depth_map_fbo.texture_id);
            player.draw(player_emissive_shader);

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

            // log.info("drawing bullet_store ", .{});
            bullet_store.drawBullets(instanced_matrix_shader, &state.active_camera.getProjectionView());

            // const debug_emission = false;
            // if (debug_emission) {
            //     const texture_unit = 0;
            //     gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            //     gl.viewport(0, 0, viewport_width, viewport_height);
            //     gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
            //
            //     gl.activeTexture(gl.TEXTURE0 + texture_unit);
            //     gl.bindTexture(gl.TEXTURE_2D, emissions_fbo.texture_id);
            //
            //     basicer_shader.useShader();
            //     basicer_shader.setBool("greyscale", false);
            //     basicer_shader.setInt("tex", texture_unit);
            //
            //     // log.info("drawing quads ", .{});
            //     quads.drawQuad(&quad_vao);
            //
            //     window.swap_buffers();
            //     continue;
            // }
        }

        // const debug_depth = true;
        // if (debug_depth) {
        //     gl.activeTexture(gl.TEXTURE0);
        //     gl.bindTexture(gl.TEXTURE_2D, depth_map_fbo.texture_id);
        //     gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        //
        //     _debug_depth_shader.useShader();
        //     _debug_depth_shader.setFloat("near_plane", near_plane);
        //     _debug_depth_shader.setFloat("far_plane", far_plane);
        //     quads.drawQuad(&quad_vao);
        // }

        // draw to scene buffer for base texture
        if (use_framebuffers) {
            gl.bindFramebuffer(gl.FRAMEBUFFER, scene_fbo.framebuffer_id);
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
            gl.clearColor(0.0, 0.02, 0.25, 1.0);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        } else {
            gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
        }

        // read from depth map fbo
        floor_shader.bindTextureAuto("shadow_map", depth_map_fbo.texture_id);
        player_shader.bindTextureAuto("shadow_map", depth_map_fbo.texture_id);

        floor_shader.useShader();
        floor_shader.setBool("useLight", true);
        floor_shader.setBool("useSpec", true);

        // log.info("drawing floor", .{});
        floor.draw(floor_shader, &state.active_camera.getProjectionView());

        player_shader.useShader();
        player_shader.setBool("useLight", true);
        player_shader.setBool("useEmissive", true);
        player_shader.setBool("depth_mode", false);

        // log.info("drawing player", .{});
        player.draw(player_shader);

        muzzle_flash.draw(sprite_shader, &state.active_camera.getProjectionView(), &muzzle_transform);

        enemy_shader.useShader();
        enemy_shader.setBool("useLight", true);
        enemy_shader.setBool("useEmissive", false);
        enemy_shader.setBool("depth_mode", false);

        // log.info("drawing enemies", .{});
        enemy_system.drawEnemies(enemy_shader, &state);

        // log.debug("drawing burn_marks", .{});
        state.burn_marks.drawMarks(basic_texture_shader, &state.active_camera.getProjectionView(), state.delta_time);

        // log.info("drawing bullet_impacts", .{});
        bullet_store.drawBulletImpacts(sprite_shader, &state.active_camera.getProjectionView());

        if (!use_framebuffers) {
            bullet_store.drawBullets(instanced_matrix_shader, &state.active_camera.getProjectionView());
        }

        if (use_framebuffers) {
            // generated blur and combine with emission and scene for final draw to framebuffer 0
            // gl.Disable(gl.DEPTH_TEST);

            // view port for blur effect
            gl.viewport(0, 0, @intFromFloat(viewport_width / BLUR_SCALE), @intFromFloat(viewport_height / BLUR_SCALE));

            // Draw horizontal blur
            gl.bindFramebuffer(gl.FRAMEBUFFER, horizontal_blur_fbo.framebuffer_id);
            gl.bindVertexArray(more_obnoxious_quad_vao);

            blur_shader.bindTextureAuto("image", emissions_fbo.texture_id);

            blur_shader.useShader();
            blur_shader.setBool("horizontal", true);

            gl.drawArrays(gl.TRIANGLES, 0, 6);

            // Draw vertical blur
            gl.bindFramebuffer(gl.FRAMEBUFFER, vertical_blur_fbo.framebuffer_id);
            gl.bindVertexArray(more_obnoxious_quad_vao);

            blur_shader.bindTextureAuto("image", horizontal_blur_fbo.texture_id);

            blur_shader.useShader();
            blur_shader.setBool("horizontal", false);

            gl.drawArrays(gl.TRIANGLES, 0, 6);

            // view port for final draw combining everything
            gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));

            gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            gl.bindVertexArray(more_obnoxious_quad_vao);

            scene_draw_shader.useShader();

            scene_draw_shader.bindTextureAuto("base_texture", scene_fbo.texture_id);
            scene_draw_shader.bindTextureAuto("emission_texture", vertical_blur_fbo.texture_id);
            scene_draw_shader.bindTextureAuto("bright_texture", emissions_fbo.texture_id);

            gl.drawArrays(gl.TRIANGLES, 0, 6);

            // gl.Enable(gl.DEPTH_TEST);

            // const debug_blur = false;
            // if (debug_blur) {
            //     const texture_unit = 0;
            //     gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            //
            //     gl.viewport(0, 0, @intFromFloat(viewport_width), @intFromFloat(viewport_height));
            //     gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
            //
            //     gl.activeTexture(gl.TEXTURE0 + texture_unit);
            //     gl.bindTexture(gl.TEXTURE_2D, scene_fbo.texture_id);
            //
            //     basicer_shader.useShader();
            //     basicer_shader.setBool("greyscale", false);
            //     basicer_shader.setInt("tex", texture_unit);
            //
            //     quads.drawQuad(&quad_vao);
            //
            //     window.swap_buffers();
            //     continue;
            // }
        }

        window.swapBuffers();
    }

    log.info("\nRun completed.\n", .{});
}

fn framebufferCreate(viewport_width: f32, viewport_height: f32) void {
    depth_map_fbo = fb.createDepthMapFbo();
    emissions_fbo = fb.createEmissionFbo(viewport_width, viewport_height);
    scene_fbo = fb.createSceneFbo(viewport_width, viewport_height);
    horizontal_blur_fbo = fb.createHorizontalBlurFbo(viewport_width, viewport_height);
    vertical_blur_fbo = fb.createVerticalBlurFbo(viewport_width, viewport_height);
}

fn framebufferUpdate(viewport_width: f32, viewport_height: f32, use_framebuffers: bool) void {
    if (use_framebuffers) {
        emissions_fbo.deinit();
        scene_fbo.deinit();
        horizontal_blur_fbo.deinit();
        vertical_blur_fbo.deinit();

        emissions_fbo = fb.createEmissionFbo(viewport_width, viewport_height);
        scene_fbo = fb.createSceneFbo(viewport_width, viewport_height);
        horizontal_blur_fbo = fb.createHorizontalBlurFbo(viewport_width, viewport_height);
        vertical_blur_fbo = fb.createVerticalBlurFbo(viewport_width, viewport_height);
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
