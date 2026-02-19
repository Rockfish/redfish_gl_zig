const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Core Types
// ============================================================================

pub const GlslType = enum {
    float,
    vec2,
    vec3,
    vec4,
    mat3,
    mat4,
    int,
    ivec2,
    ivec3,
    ivec4,
    uint,
    uvec2,
    uvec3,
    uvec4,
    sampler2D,
    sampler3D,
    samplerCube,
    sampler2DArray,

    pub fn toGlsl(self: GlslType) []const u8 {
        return switch (self) {
            .float => "float",
            .vec2 => "vec2",
            .vec3 => "vec3",
            .vec4 => "vec4",
            .mat3 => "mat3",
            .mat4 => "mat4",
            .int => "int",
            .ivec2 => "ivec2",
            .ivec3 => "ivec3",
            .ivec4 => "ivec4",
            .uint => "uint",
            .uvec2 => "uvec2",
            .uvec3 => "uvec3",
            .uvec4 => "uvec4",
            .sampler2D => "sampler2D",
            .sampler3D => "sampler3D",
            .samplerCube => "samplerCube",
            .sampler2DArray => "sampler2DArray",
        };
    }

    pub fn fromString(s: []const u8) ?GlslType {
        const map = std.StaticStringMap(GlslType).initComptime(.{
            .{ "float", .float },
            .{ "vec2", .vec2 },
            .{ "vec3", .vec3 },
            .{ "vec4", .vec4 },
            .{ "mat3", .mat3 },
            .{ "mat4", .mat4 },
            .{ "int", .int },
            .{ "ivec2", .ivec2 },
            .{ "ivec3", .ivec3 },
            .{ "ivec4", .ivec4 },
            .{ "uint", .uint },
            .{ "uvec2", .uvec2 },
            .{ "uvec3", .uvec3 },
            .{ "uvec4", .uvec4 },
            .{ "sampler2D", .sampler2D },
            .{ "sampler3D", .sampler3D },
            .{ "samplerCube", .samplerCube },
            .{ "sampler2DArray", .sampler2DArray },
        });
        return map.get(s);
    }
};

pub const Variable = struct {
    name: []const u8,
    type: GlslType,
    default: ?[]const u8 = null, // For uniforms with defaults
};

pub const VertexAttribute = struct {
    name: []const u8,
    type: GlslType,
    location: ?u32 = null, // If null, auto-assigned in order
};

pub const UniformBinding = struct {
    name: []const u8,
    type: GlslType,
    binding: u32,
    set: u32 = 0, // For Vulkan compatibility, ignored in GL
};

pub const UniformBlock = struct {
    name: []const u8,
    binding: u32,
    set: u32 = 0,
    members: []const Variable,
};

// ============================================================================
// Module Definition (parsed from .module files)
// ============================================================================

pub const ShaderModule = struct {
    name: []const u8,
    stage: ShaderStage,
    requires: []const Variable, // Variables this module reads
    provides: []const Variable, // Variables this module writes
    uniforms: []const UniformBinding, // Module-specific uniforms
    uniform_blocks: []const UniformBlock,
    code: []const u8, // The actual GLSL code body

    pub const ShaderStage = enum {
        vertex,
        fragment,
        common, // Can be used in either
    };
};

// ============================================================================
// Shader Recipe (what you write to define a shader)
// ============================================================================

pub const ShaderRecipe = struct {
    name: []const u8,
    vertex_modules: []const []const u8,
    fragment_modules: []const []const u8,
    vertex_inputs: []const VertexAttribute,
    vertex_outputs: []const Variable, // Varyings
    uniforms: []const UniformBinding, // Recipe-level uniforms
    uniform_blocks: []const UniformBlock,
    defines: []const Define = &.{},

    pub const Define = struct {
        name: []const u8,
        value: ?[]const u8 = null,
    };
};

// ============================================================================
// Module Parser
// ============================================================================

pub const ModuleParser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ModuleParser {
        return .{ .allocator = allocator };
    }

    /// Parse a .module file into a ShaderModule
    /// Format:
    /// //! stage: vertex|fragment|common
    /// //! requires: type name, type name, ...
    /// //! provides: type name, type name, ...
    /// //! uniform: type name binding=N
    /// //! block: BlockName binding=N { type member; type member; }
    ///
    /// <actual GLSL code>
    pub fn parse(self: *ModuleParser, name: []const u8, source: []const u8) !ShaderModule {
        var requires = std.ArrayList(Variable).init(self.allocator);
        var provides = std.ArrayList(Variable).init(self.allocator);
        var uniforms = std.ArrayList(UniformBinding).init(self.allocator);
        var uniform_blocks = std.ArrayList(UniformBlock).init(self.allocator);

        var stage: ShaderModule.ShaderStage = .common;
        var code_start: usize = 0;

        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_num: usize = 0;

        while (lines.next()) |line| {
            line_num += 1;
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (std.mem.startsWith(u8, trimmed, "//!")) {
                const directive = std.mem.trim(u8, trimmed[3..], " \t");
                try self.parseDirective(directive, &stage, &requires, &provides, &uniforms, &uniform_blocks);
                code_start = lines.index orelse source.len;
            } else if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "//")) {
                // First non-comment, non-directive line is start of code
                break;
            }
        }

        return ShaderModule{
            .name = try self.allocator.dupe(u8, name),
            .stage = stage,
            .requires = try requires.toOwnedSlice(),
            .provides = try provides.toOwnedSlice(),
            .uniforms = try uniforms.toOwnedSlice(),
            .uniform_blocks = try uniform_blocks.toOwnedSlice(),
            .code = std.mem.trim(u8, source[code_start..], " \t\r\n"),
        };
    }

    fn parseDirective(
        self: *ModuleParser,
        directive: []const u8,
        stage: *ShaderModule.ShaderStage,
        requires: *std.ArrayList(Variable),
        provides: *std.ArrayList(Variable),
        uniforms: *std.ArrayList(UniformBinding),
        uniform_blocks: *std.ArrayList(UniformBlock),
    ) !void {
        if (std.mem.startsWith(u8, directive, "stage:")) {
            const value = std.mem.trim(u8, directive[6..], " \t");
            stage.* = if (std.mem.eql(u8, value, "vertex"))
                .vertex
            else if (std.mem.eql(u8, value, "fragment"))
                .fragment
            else
                .common;
        } else if (std.mem.startsWith(u8, directive, "requires:")) {
            try self.parseVariableList(directive[9..], requires);
        } else if (std.mem.startsWith(u8, directive, "provides:")) {
            try self.parseVariableList(directive[9..], provides);
        } else if (std.mem.startsWith(u8, directive, "uniform:")) {
            try self.parseUniform(directive[8..], uniforms);
        } else if (std.mem.startsWith(u8, directive, "block:")) {
            try self.parseUniformBlock(directive[6..], uniform_blocks);
        }
    }

    fn parseVariableList(self: *ModuleParser, list: []const u8, out: *std.ArrayList(Variable)) !void {
        var items = std.mem.splitScalar(u8, list, ',');
        while (items.next()) |item| {
            const trimmed = std.mem.trim(u8, item, " \t");
            if (trimmed.len == 0) continue;

            var parts = std.mem.splitScalar(u8, trimmed, ' ');
            const type_str = parts.next() orelse continue;
            const name_str = parts.next() orelse continue;

            const glsl_type = GlslType.fromString(type_str) orelse continue;

            try out.append(.{
                .name = try self.allocator.dupe(u8, name_str),
                .type = glsl_type,
            });
        }
    }

    fn parseUniform(self: *ModuleParser, decl: []const u8, out: *std.ArrayList(UniformBinding)) !void {
        // Format: type name binding=N [set=M]
        const trimmed = std.mem.trim(u8, decl, " \t");
        var parts = std.mem.splitScalar(u8, trimmed, ' ');

        const type_str = parts.next() orelse return;
        const name_str = parts.next() orelse return;

        const glsl_type = GlslType.fromString(type_str) orelse return;

        var binding: u32 = 0;
        var set: u32 = 0;

        while (parts.next()) |part| {
            if (std.mem.startsWith(u8, part, "binding=")) {
                binding = std.fmt.parseInt(u32, part[8..], 10) catch 0;
            } else if (std.mem.startsWith(u8, part, "set=")) {
                set = std.fmt.parseInt(u32, part[4..], 10) catch 0;
            }
        }

        try out.append(.{
            .name = try self.allocator.dupe(u8, name_str),
            .type = glsl_type,
            .binding = binding,
            .set = set,
        });
    }

    fn parseUniformBlock(self: *ModuleParser, decl: []const u8, out: *std.ArrayList(UniformBlock)) !void {
        // Format: BlockName binding=N { type member; type member; }
        const trimmed = std.mem.trim(u8, decl, " \t");

        // Find the block name (first word)
        var name_end: usize = 0;
        for (trimmed, 0..) |c, i| {
            if (c == ' ' or c == '{') {
                name_end = i;
                break;
            }
        }
        if (name_end == 0) return;

        const block_name = trimmed[0..name_end];

        // Find binding
        var binding: u32 = 0;
        var set: u32 = 0;
        if (std.mem.indexOf(u8, trimmed, "binding=")) |idx| {
            var end = idx + 8;
            while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) : (end += 1) {}
            binding = std.fmt.parseInt(u32, trimmed[idx + 8 .. end], 10) catch 0;
        }
        if (std.mem.indexOf(u8, trimmed, "set=")) |idx| {
            var end = idx + 4;
            while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) : (end += 1) {}
            set = std.fmt.parseInt(u32, trimmed[idx + 4 .. end], 10) catch 0;
        }

        // Find members between { }
        const brace_start = std.mem.indexOf(u8, trimmed, "{") orelse return;
        const brace_end = std.mem.lastIndexOf(u8, trimmed, "}") orelse return;
        const members_str = trimmed[brace_start + 1 .. brace_end];

        var members = std.ArrayList(Variable).init(self.allocator);
        var member_decls = std.mem.splitScalar(u8, members_str, ';');
        while (member_decls.next()) |member_decl| {
            const member_trimmed = std.mem.trim(u8, member_decl, " \t\r\n");
            if (member_trimmed.len == 0) continue;

            var parts = std.mem.splitScalar(u8, member_trimmed, ' ');
            const type_str = parts.next() orelse continue;
            const name_str = parts.next() orelse continue;

            const glsl_type = GlslType.fromString(type_str) orelse continue;
            try members.append(.{
                .name = try self.allocator.dupe(u8, name_str),
                .type = glsl_type,
            });
        }

        try out.append(.{
            .name = try self.allocator.dupe(u8, block_name),
            .binding = binding,
            .set = set,
            .members = try members.toOwnedSlice(),
        });
    }
};

// ============================================================================
// Shader Generator
// ============================================================================

pub const ShaderGenerator = struct {
    allocator: Allocator,
    modules: std.StringHashMap(ShaderModule),
    module_search_paths: []const []const u8,

    pub fn init(allocator: Allocator, search_paths: []const []const u8) ShaderGenerator {
        return .{
            .allocator = allocator,
            .modules = std.StringHashMap(ShaderModule).init(allocator),
            .module_search_paths = search_paths,
        };
    }

    pub fn deinit(self: *ShaderGenerator) void {
        self.modules.deinit();
    }

    /// Load a module from file and cache it
    pub fn loadModule(self: *ShaderGenerator, name: []const u8) !ShaderModule {
        if (self.modules.get(name)) |cached| {
            return cached;
        }

        // Try to find the module file
        for (self.module_search_paths) |path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ path, name });
            defer self.allocator.free(full_path);

            const with_ext = try std.mem.concat(self.allocator, u8, &.{ full_path, ".module" });
            defer self.allocator.free(with_ext);

            const file = std.fs.cwd().openFile(with_ext, .{}) catch continue;
            defer file.close();

            const source = try file.readToEndAlloc(self.allocator, 1024 * 1024);
            defer self.allocator.free(source);

            var parser = ModuleParser.init(self.allocator);
            const module = try parser.parse(name, source);
            try self.modules.put(try self.allocator.dupe(u8, name), module);
            return module;
        }

        return error.ModuleNotFound;
    }

    /// Register a module directly (useful for built-in modules)
    pub fn registerModule(self: *ShaderGenerator, module: ShaderModule) !void {
        try self.modules.put(module.name, module);
    }

    /// Generate complete vertex and fragment shaders from a recipe
    pub fn generate(self: *ShaderGenerator, recipe: ShaderRecipe) !GeneratedShader {
        // Load all modules
        var vertex_modules = std.ArrayList(ShaderModule).init(self.allocator);
        defer vertex_modules.deinit();
        var fragment_modules = std.ArrayList(ShaderModule).init(self.allocator);
        defer fragment_modules.deinit();

        for (recipe.vertex_modules) |name| {
            try vertex_modules.append(try self.loadModule(name));
        }
        for (recipe.fragment_modules) |name| {
            try fragment_modules.append(try self.loadModule(name));
        }

        // Validate dataflow
        try self.validateDataflow(vertex_modules.items, recipe.vertex_inputs, recipe.vertex_outputs);
        try self.validateDataflow(fragment_modules.items, recipe.vertex_outputs, null);

        // Collect all uniforms (recipe + modules)
        var all_uniforms = std.ArrayList(UniformBinding).init(self.allocator);
        defer all_uniforms.deinit();
        var all_blocks = std.ArrayList(UniformBlock).init(self.allocator);
        defer all_blocks.deinit();

        for (recipe.uniforms) |u| try all_uniforms.append(u);
        for (recipe.uniform_blocks) |b| try all_blocks.append(b);

        for (vertex_modules.items) |m| {
            for (m.uniforms) |u| try all_uniforms.append(u);
            for (m.uniform_blocks) |b| try all_blocks.append(b);
        }
        for (fragment_modules.items) |m| {
            for (m.uniforms) |u| try all_uniforms.append(u);
            for (m.uniform_blocks) |b| try all_blocks.append(b);
        }

        // Generate vertex shader
        const vertex_source = try self.generateStage(
            .vertex,
            vertex_modules.items,
            recipe,
            all_uniforms.items,
            all_blocks.items,
        );

        // Generate fragment shader
        const fragment_source = try self.generateStage(
            .fragment,
            fragment_modules.items,
            recipe,
            all_uniforms.items,
            all_blocks.items,
        );

        return .{
            .name = recipe.name,
            .vertex_source = vertex_source,
            .fragment_source = fragment_source,
        };
    }

    fn validateDataflow(
        self: *ShaderGenerator,
        modules: []const ShaderModule,
        initial_provides: anytype,
        required_outputs: ?[]const Variable,
    ) !void {
        _ = self;
        var available = std.StringHashMap(GlslType).init(self.allocator);
        defer available.deinit();

        // Start with initial provides (vertex inputs or varyings)
        for (initial_provides) |v| {
            try available.put(v.name, v.type);
        }

        // Process each module in order
        for (modules) |module| {
            // Check all requirements are met
            for (module.requires) |req| {
                if (available.get(req.name)) |available_type| {
                    if (available_type != req.type) {
                        std.debug.print("Type mismatch for '{s}': module expects {s}, got {s}\n", .{
                            req.name,
                            req.type.toGlsl(),
                            available_type.toGlsl(),
                        });
                        return error.TypeMismatch;
                    }
                } else {
                    std.debug.print("Module '{s}' requires '{s}' but it's not available\n", .{
                        module.name,
                        req.name,
                    });
                    return error.UnmetRequirement;
                }
            }

            // Add this module's provides
            for (module.provides) |prov| {
                try available.put(prov.name, prov.type);
            }
        }

        // Check final required outputs
        if (required_outputs) |outputs| {
            for (outputs) |out| {
                if (!available.contains(out.name)) {
                    std.debug.print("Required output '{s}' not provided by any module\n", .{out.name});
                    return error.MissingOutput;
                }
            }
        }
    }

    fn generateStage(
        self: *ShaderGenerator,
        stage: ShaderModule.ShaderStage,
        modules: []const ShaderModule,
        recipe: ShaderRecipe,
        uniforms: []const UniformBinding,
        blocks: []const UniformBlock,
    ) ![]const u8 {
        var output = std.ArrayList(u8).init(self.allocator);
        const writer = output.writer();

        // Version and defines
        try writer.writeAll("#version 450\n\n");

        for (recipe.defines) |define| {
            if (define.value) |val| {
                try writer.print("#define {s} {s}\n", .{ define.name, val });
            } else {
                try writer.print("#define {s}\n", .{define.name});
            }
        }
        try writer.writeAll("\n");

        // Vertex inputs (only for vertex stage)
        if (stage == .vertex) {
            try writer.writeAll("// Vertex Inputs\n");
            for (recipe.vertex_inputs, 0..) |attr, i| {
                const loc = attr.location orelse @as(u32, @intCast(i));
                try writer.print("layout(location = {}) in {s} {s};\n", .{
                    loc,
                    attr.type.toGlsl(),
                    attr.name,
                });
            }
            try writer.writeAll("\n");
        }

        // Varyings
        if (recipe.vertex_outputs.len > 0) {
            try writer.writeAll("// Varyings\n");
            const qualifier: []const u8 = if (stage == .vertex) "out" else "in";
            for (recipe.vertex_outputs, 0..) |varying, i| {
                try writer.print("layout(location = {}) {s} {s} {s};\n", .{
                    i,
                    qualifier,
                    varying.type.toGlsl(),
                    varying.name,
                });
            }
            try writer.writeAll("\n");
        }

        // Fragment outputs (only for fragment stage)
        if (stage == .fragment) {
            try writer.writeAll("// Fragment Outputs\n");
            try writer.writeAll("layout(location = 0) out vec4 frag_color;\n\n");
        }

        // Uniform blocks
        if (blocks.len > 0) {
            try writer.writeAll("// Uniform Blocks\n");
            for (blocks) |block| {
                try writer.print("layout(std140, binding = {}) uniform {s} {{\n", .{
                    block.binding,
                    block.name,
                });
                for (block.members) |member| {
                    try writer.print("    {s} {s};\n", .{ member.type.toGlsl(), member.name });
                }
                try writer.writeAll("};\n\n");
            }
        }

        // Standalone uniforms
        const standalone_uniforms = try self.filterStandaloneUniforms(uniforms, blocks);
        defer self.allocator.free(standalone_uniforms);

        if (standalone_uniforms.len > 0) {
            try writer.writeAll("// Uniforms\n");
            for (standalone_uniforms) |uniform| {
                try writer.print("layout(binding = {}) uniform {s} {s};\n", .{
                    uniform.binding,
                    uniform.type.toGlsl(),
                    uniform.name,
                });
            }
            try writer.writeAll("\n");
        }

        // Intermediate variables (provides from each module)
        try writer.writeAll("// Module variables\n");
        var declared = std.StringHashMap(void).init(self.allocator);
        defer declared.deinit();

        // Mark inputs as declared
        if (stage == .vertex) {
            for (recipe.vertex_inputs) |attr| {
                try declared.put(attr.name, {});
            }
        } else {
            for (recipe.vertex_outputs) |varying| {
                try declared.put(varying.name, {});
            }
        }

        // Declare module provides
        for (modules) |module| {
            for (module.provides) |prov| {
                if (!declared.contains(prov.name)) {
                    try writer.print("{s} {s};\n", .{ prov.type.toGlsl(), prov.name });
                    try declared.put(prov.name, {});
                }
            }
        }
        try writer.writeAll("\n");

        // Module code bodies
        for (modules) |module| {
            try writer.print("// --- Module: {s} ---\n", .{module.name});
            try writer.writeAll(module.code);
            try writer.writeAll("\n\n");
        }

        // Generate main()
        try writer.writeAll("void main() {\n");
        for (modules) |module| {
            // Call the module's entry function (convention: module name with / replaced by _)
            var func_name = try self.allocator.alloc(u8, module.name.len);
            defer self.allocator.free(func_name);
            for (module.name, 0..) |c, i| {
                func_name[i] = if (c == '/') '_' else c;
            }
            try writer.print("    {s}();\n", .{func_name});
        }

        // Final output assignment
        if (stage == .fragment) {
            try writer.writeAll("    frag_color = final_color;\n");
        }

        try writer.writeAll("}\n");

        return output.toOwnedSlice();
    }

    fn filterStandaloneUniforms(self: *ShaderGenerator, uniforms: []const UniformBinding, blocks: []const UniformBlock) ![]const UniformBinding {
        var result = std.ArrayList(UniformBinding).init(self.allocator);

        // Collect all member names from blocks
        var block_members = std.StringHashMap(void).init(self.allocator);
        defer block_members.deinit();

        for (blocks) |block| {
            for (block.members) |member| {
                try block_members.put(member.name, {});
            }
        }

        // Only include uniforms not in blocks
        for (uniforms) |uniform| {
            if (!block_members.contains(uniform.name)) {
                try result.append(uniform);
            }
        }

        return result.toOwnedSlice();
    }
};

pub const GeneratedShader = struct {
    name: []const u8,
    vertex_source: []const u8,
    fragment_source: []const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "parse simple module" {
    const source =
        \\//! stage: fragment
        \\//! requires: vec3 world_normal, vec3 view_dir
        \\//! provides: vec3 lit_color
        \\//! uniform: sampler2D diffuse_map binding=0
        \\
        \\void lighting_basic() {
        \\    float ndotl = max(dot(world_normal, vec3(0, 1, 0)), 0.0);
        \\    lit_color = vec3(ndotl);
        \\}
    ;

    var parser = ModuleParser.init(std.testing.allocator);
    const module = try parser.parse("lighting/basic", source);
    defer {
        std.testing.allocator.free(module.name);
        for (module.requires) |r| std.testing.allocator.free(r.name);
        std.testing.allocator.free(module.requires);
        for (module.provides) |p| std.testing.allocator.free(p.name);
        std.testing.allocator.free(module.provides);
        for (module.uniforms) |u| std.testing.allocator.free(u.name);
        std.testing.allocator.free(module.uniforms);
        std.testing.allocator.free(module.uniform_blocks);
    }

    try std.testing.expectEqual(ShaderModule.ShaderStage.fragment, module.stage);
    try std.testing.expectEqual(@as(usize, 2), module.requires.len);
    try std.testing.expectEqual(@as(usize, 1), module.provides.len);
    try std.testing.expectEqual(@as(usize, 1), module.uniforms.len);
    try std.testing.expectEqualStrings("diffuse_map", module.uniforms[0].name);
    try std.testing.expectEqual(@as(u32, 0), module.uniforms[0].binding);
}
