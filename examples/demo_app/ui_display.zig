const std = @import("std");
const math = std.math;
const glfw = @import("zglfw");
const zgui = @import("zgui");
const core = @import("core");

const state = @import("state.zig");
const assets_list = @import("assets_list.zig");

const Allocator = std.mem.Allocator;
const content_dir = @import("build_options").content_dir;

pub const UIState = struct {
    show_model_info: bool = true,
    show_performance: bool = true,
    help_toggle_timer: f32 = 0.0,
    last_model_change_time: f32 = 0.0,
    scale_factor: f32 = 1.0,
    font_normal: ?zgui.Font = null,
    font_mono: ?zgui.Font = null,
    current_width: f32 = 0.0,
    current_height: f32 = 0.0,
    
    // Performance tracking
    frame_counter: core.FrameCounter = undefined,
    last_load_time: f32 = 0.0,
    
    const Self = @This();
    
    pub fn init(allocator: Allocator, window: *glfw.Window) !Self {
        var ui_state = Self{};
        
        // Initialize zgui
        zgui.init(allocator);
        
        // Calculate scale factor
        const scale = window.getContentScale();
        ui_state.scale_factor = @max(scale[0], scale[1]);
        
        // Load fonts
        const font_size = 14.0 * ui_state.scale_factor;
        ui_state.font_mono = zgui.io.addFontFromFile(content_dir ++ "fonts/FiraCode-Medium.ttf", math.floor(font_size));
        ui_state.font_normal = zgui.io.addFontFromFile(content_dir ++ "fonts/Roboto-Medium.ttf", math.floor(font_size));
        
        // Initialize backend
        zgui.backend.init(window);
        
        // Set default font
        if (ui_state.font_normal) |font| {
            zgui.io.setDefaultFont(font);
        }
        
        // Style the UI
        ui_state.setupStyle();
        
        // Initialize frame counter
        ui_state.frame_counter = core.FrameCounter.init();
        
        return ui_state;
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
        zgui.backend.deinit();
        zgui.deinit();
    }
    
    fn setupStyle(self: *Self) void {
        const style = zgui.getStyle();
        
        // Window styling
        style.window_min_size = .{ 200.0, 100.0 };
        style.window_rounding = 6.0;
        style.window_padding = .{ 8.0, 6.0 };
        style.frame_rounding = 4.0;
        
        // Colors for dark theme
        style.setColor(.window_bg, .{ 0.1, 0.1, 0.1, 0.9 });
        style.setColor(.text, .{ 0.9, 0.9, 0.9, 1.0 });
        style.setColor(.border, .{ 0.3, 0.3, 0.3, 1.0 });
        
        // Scale all sizes
        style.scaleAllSizes(self.scale_factor);
    }
    
    pub fn update(self: *Self, window: *glfw.Window) void {
        self.frame_counter.update();
        
        // Get current window size for accurate positioning
        const fb_size = window.getFramebufferSize();
        self.current_width = @floatFromInt(fb_size[0]);
        self.current_height = @floatFromInt(fb_size[1]);
        
        // Track when help is shown for auto-hide timer
        if (state.state.ui_help_visible and self.help_toggle_timer == 0.0) {
            self.help_toggle_timer = state.state.total_time;
        }
        
        // Auto-hide help after 10 seconds
        if (state.state.ui_help_visible and (state.state.total_time - self.help_toggle_timer) > 10.0) {
            // Reset the timer when auto-hiding
            self.help_toggle_timer = 0.0;
        }
        
        // Track model changes for auto-show
        if (state.state.model_reload_requested) {
            self.last_model_change_time = state.state.total_time;
        }
        
        // Start new frame
        zgui.backend.newFrame(
            @intFromFloat(self.current_width),
            @intFromFloat(self.current_height),
        );
    }
    
    pub fn render(self: *Self) void {
        if (self.show_model_info) {
            self.renderModelInfo();
        }
        
        if (self.show_performance) {
            self.renderPerformance();
        }
        
        if (state.state.ui_camera_info_visible) {
            self.renderCameraInfo();
        }
        
        if (state.state.ui_help_visible) {
            self.renderHelp();
        }
        
        // Render the UI
        zgui.backend.draw();
    }
    
    fn renderModelInfo(self: *Self) void {
        const current_model = state.getCurrentModel();
        const total_models = assets_list.demo_models.len;
        const current_index = state.state.current_model_index;
        
        // Position at top-left
        zgui.setNextWindowPos(.{ .x = 10.0, .y = 10.0, .cond = .always });
        
        const window_flags = zgui.WindowFlags{
            .no_resize = true,
            .no_move = true,
            .no_collapse = true,
            .no_title_bar = true,
            .always_auto_resize = true,
        };
        
        if (zgui.begin("Model Info", .{ .flags = window_flags })) {
            // Use monospace font for structured info
            if (self.font_mono) |font| {
                zgui.pushFont(font);
            }
            
            // Model counter and name
            zgui.textColored(.{ 0.7, 0.9, 1.0, 1.0 }, "{d}/{d}: {s}", .{ current_index + 1, total_models, current_model.name });
            
            // Format and category
            const format_color: [4]f32 = if (std.mem.eql(u8, current_model.format, "GLB")) 
                .{ 0.9, 0.7, 0.3, 1.0 } else .{ 0.3, 0.9, 0.7, 1.0 };
            zgui.textColored(format_color, "{s}", .{current_model.format});
            zgui.sameLine(.{});
            zgui.textColored(.{ 0.8, 0.8, 0.8, 1.0 }, " - {s}", .{current_model.category});
            
            // Description
            zgui.textWrapped("{s}", .{current_model.description});
            
            if (self.font_mono) |_| {
                zgui.popFont();
            }
        }
        zgui.end();
    }
    
    fn renderPerformance(self: *Self) void {
        // Position at top-right (manual calculation since zgui doesn't have pivot)
        zgui.setNextWindowPos(.{ .x = self.current_width - 150.0, .y = 10.0, .cond = .always });
        
        const window_flags = zgui.WindowFlags{
            .no_resize = true,
            .no_move = true,
            .no_collapse = true,
            .no_title_bar = true,
            .always_auto_resize = true,
        };
        
        if (zgui.begin("Performance", .{ .flags = window_flags })) {
            if (self.font_mono) |font| {
                zgui.pushFont(font);
            }
            
            // FPS and frame time
            zgui.textColored(.{ 0.9, 0.9, 0.3, 1.0 }, "{d:.1} fps", .{self.frame_counter.fps});
            zgui.textColored(.{ 0.7, 0.7, 0.7, 1.0 }, "{d:.1}ms/frame", .{self.frame_counter.frame_time});
            
            // Show load time if recent
            if (self.last_load_time > 0.0) {
                zgui.textColored(.{ 0.6, 0.9, 0.6, 1.0 }, "Load: {d:.1}s", .{self.last_load_time});
            }
            
            if (self.font_mono) |_| {
                zgui.popFont();
            }
        }
        zgui.end();
    }
    
    fn renderCameraInfo(self: *Self) void {
        // Position on the right side, below performance metrics
        zgui.setNextWindowPos(.{ .x = self.current_width - 280.0, .y = 100.0, .cond = .always });
        
        const window_flags = zgui.WindowFlags{
            .no_resize = true,
            .no_move = true,
            .no_collapse = true,
            .no_title_bar = true,
            .always_auto_resize = true,
        };
        
        if (zgui.begin("Camera Info", .{ .flags = window_flags })) {
            if (self.font_mono) |font| {
                zgui.pushFont(font);
            }
            
            // Camera position
            const cam_pos = state.state.camera.movement.position;
            zgui.textColored(.{ 0.7, 0.9, 1.0, 1.0 }, "Camera:", .{});
            zgui.text("  Pos: {d:.1}, {d:.1}, {d:.1}", .{ cam_pos.x, cam_pos.y, cam_pos.z });
            
            // Camera target
            const cam_target = state.state.camera.movement.target;
            zgui.text("  Target: {d:.1}, {d:.1}, {d:.1}", .{ cam_target.x, cam_target.y, cam_target.z });
            
            zgui.separator();
            
            // Movement type
            const motion_type_str = switch (state.state.motion_type) {
                .Translate => "Translate",
                .Orbit => "Orbit",
                .Circle => "Circle",
                .Rotate => "Rotate",
            };
            zgui.textColored(.{ 0.9, 0.7, 0.3, 1.0 }, "Motion:", .{});
            zgui.text("  {s}", .{motion_type_str});
            
            // View type
            const view_type_str = switch (state.state.camera.view_type) {
                .LookTo => "LookTo",
                .LookAt => "LookAt",
            };
            zgui.text("  View: {s}", .{view_type_str});
            
            // Projection type
            const proj_type_str = switch (state.state.camera.projection_type) {
                .Perspective => "Perspective",
                .Orthographic => "Orthographic",
            };
            zgui.text("  Proj: {s}", .{proj_type_str});
            
            if (self.font_mono) |_| {
                zgui.popFont();
            }
        }
        zgui.end();
    }
    
    fn renderHelp(self: *Self) void {
        // Position at bottom-left (manual calculation since zgui doesn't have pivot)
        zgui.setNextWindowPos(.{ .x = 10.0, .y = self.current_height - 280.0, .cond = .always });
        
        const window_flags = zgui.WindowFlags{
            .no_resize = true,
            .no_move = true,
            .no_collapse = true,
            .always_auto_resize = true,
        };
        
        if (zgui.begin("Controls", .{ .flags = window_flags })) {
            zgui.textColored(.{ 1.0, 0.8, 0.4, 1.0 }, "Model Navigation:", .{});
            zgui.text("  N/B     Next/Previous model", .{});
            zgui.text("  F       Frame to fit", .{});
            zgui.text("  R       Reset camera", .{});
            
            zgui.separator();
            
            zgui.textColored(.{ 1.0, 0.8, 0.4, 1.0 }, "Camera Controls:", .{});
            zgui.text("  WASD    Move camera", .{});
            zgui.text("  Mouse   Scroll to zoom", .{});
            zgui.text("  1/2     LookTo/LookAt mode", .{});
            zgui.text("  6-9     Motion type", .{});
            
            zgui.separator();
            
            zgui.textColored(.{ 1.0, 0.8, 0.4, 1.0 }, "Animation:", .{});
            zgui.text("  0       Reset animation", .{});
            zgui.text("  +/-     Next/Prev animation", .{});
            
            zgui.separator();
            
            zgui.textColored(.{ 1.0, 0.8, 0.4, 1.0 }, "Display Toggles:", .{});
            zgui.text("  H       Toggle help", .{});
            zgui.text("  C       Toggle camera info", .{});
            
            zgui.separator();
            
            zgui.textColored(.{ 0.7, 0.7, 0.7, 1.0 }, "Press H to hide this help", .{});
        }
        zgui.end();
    }
    
    pub fn setLoadTime(self: *Self, load_time: f32) void {
        self.last_load_time = load_time;
    }
};

