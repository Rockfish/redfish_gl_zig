// Material and texture processing for ASSIMP to glTF conversion
const std = @import("std");

// Use @cImport to access ASSIMP C functions
const assimp = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/material.h");
});

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// ASSIMP texture type constants (from material.h)
const AI_TEXTURE_TYPE_BASE_COLOR: u32 = 12; // aiTextureType_BASE_COLOR (typo in header: iTextureType_BASE_COLOR)
const AI_TEXTURE_TYPE_DIFFUSE_ROUGHNESS: u32 = 16; // aiTextureType_DIFFUSE_ROUGHNESS
const AI_TEXTURE_TYPE_METALNESS: u32 = 15; // aiTextureType_METALNESS
const AI_TEXTURE_TYPE_AMBIENT_OCCLUSION: u32 = 17; // aiTextureType_AMBIENT_OCCLUSION

// OpenGL texture filtering constants
const GL_LINEAR: u32 = 9729;
const GL_LINEAR_MIPMAP_LINEAR: u32 = 9987;

// OpenGL texture wrapping constants
const GL_REPEAT: u32 = 10497;

// Material conversion constants
const SHININESS_MAX_VALUE: f32 = 1000.0; // Maximum shininess value assumed by ASSIMP
const LUMINANCE_RED_WEIGHT: f32 = 0.2125; // ITU-R BT.709 luminance weights
const LUMINANCE_GREEN_WEIGHT: f32 = 0.7154;
const LUMINANCE_BLUE_WEIGHT: f32 = 0.0721;
const DEFAULT_ROUGHNESS: f32 = 0.9; // Default roughness for non-PBR materials
const DEFAULT_ALPHA_CUTOFF: f32 = 0.5; // Default alpha cutoff for MASK mode

// glTF material structures
pub const GltfPbrMetallicRoughness = struct {
    baseColorFactor: [4]f32 = [_]f32{ 1.0, 1.0, 1.0, 1.0 },
    baseColorTexture: ?GltfTextureInfo = null,
    metallicFactor: f32 = 1.0,
    roughnessFactor: f32 = 1.0,
    metallicRoughnessTexture: ?GltfTextureInfo = null,
};

pub const GltfTextureInfo = struct {
    index: u32,
    texCoord: u32 = 0,
};

pub const GltfNormalTextureInfo = struct {
    index: u32,
    texCoord: u32 = 0,
    scale: f32 = 1.0,
};

pub const GltfOcclusionTextureInfo = struct {
    index: u32,
    texCoord: u32 = 0,
    strength: f32 = 1.0,
};

pub const GltfMaterial = struct {
    name: []const u8,
    pbrMetallicRoughness: GltfPbrMetallicRoughness = .{},
    normalTexture: ?GltfNormalTextureInfo = null,
    occlusionTexture: ?GltfOcclusionTextureInfo = null,
    emissiveTexture: ?GltfTextureInfo = null,
    emissiveFactor: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 },
    alphaMode: []const u8 = "OPAQUE",
    alphaCutoff: f32 = 0.5,
    doubleSided: bool = false,
};

pub const GltfTexture = struct {
    source: u32,
    sampler: ?u32 = null,
};

pub const GltfImage = struct {
    uri: []const u8,
    name: ?[]const u8 = null,
};

pub const GltfSampler = struct {
    magFilter: ?u32 = null, // GL_NEAREST or GL_LINEAR
    minFilter: ?u32 = null, // GL_NEAREST, GL_LINEAR, GL_LINEAR_MIPMAP_LINEAR, etc.
    wrapS: u32 = GL_REPEAT, // GL_CLAMP_TO_EDGE, GL_MIRRORED_REPEAT, GL_REPEAT
    wrapT: u32 = GL_REPEAT,
};

pub const MaterialProcessor = struct {
    allocator: Allocator,
    input_path: []const u8,
    output_path: []const u8,
    materials: ArrayList(GltfMaterial),
    textures: ArrayList(GltfTexture),
    images: ArrayList(GltfImage),
    samplers: ArrayList(GltfSampler),
    texture_path_map: std.StringHashMap(u32), // Maps texture paths to texture indices
    verbose: bool = false,

    pub fn init(allocator: Allocator, input_path: []const u8, output_path: []const u8, verbose: bool) MaterialProcessor {
        return MaterialProcessor{
            .allocator = allocator,
            .input_path = input_path,
            .output_path = output_path,
            .materials = ArrayList(GltfMaterial).init(allocator),
            .textures = ArrayList(GltfTexture).init(allocator),
            .images = ArrayList(GltfImage).init(allocator),
            .samplers = ArrayList(GltfSampler).init(allocator),
            .texture_path_map = std.StringHashMap(u32).init(allocator),
            .verbose = verbose,
        };
    }

    pub fn deinit(self: *MaterialProcessor) void {
        // Free material names
        for (self.materials.items) |material| {
            self.allocator.free(material.name);
        }

        // Free image URIs and names
        for (self.images.items) |image| {
            self.allocator.free(image.uri);
            if (image.name) |name| {
                self.allocator.free(name);
            }
        }

        // Free texture path map keys
        var iterator = self.texture_path_map.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }

        self.materials.deinit();
        self.textures.deinit();
        self.images.deinit();
        self.samplers.deinit();
        self.texture_path_map.deinit();
    }

    pub fn processMaterials(self: *MaterialProcessor, scene: *const anyopaque) !void {
        const ai_scene: *const assimp.aiScene = @ptrCast(@alignCast(scene));
        if (self.verbose) {
            std.debug.print("Processing {d} materials...\n", .{ai_scene.mNumMaterials});
        }

        // Create default sampler (used by all textures for now)
        const default_sampler = GltfSampler{
            .magFilter = GL_LINEAR,
            .minFilter = GL_LINEAR_MIPMAP_LINEAR,
            .wrapS = GL_REPEAT,
            .wrapT = GL_REPEAT,
        };
        try self.samplers.append(default_sampler);

        for (0..ai_scene.mNumMaterials) |mat_idx| {
            const ai_material = ai_scene.mMaterials[mat_idx];
            try self.processAssimpMaterial(ai_material, mat_idx);
        }
    }

    fn processAssimpMaterial(self: *MaterialProcessor, ai_material: *const assimp.aiMaterial, mat_idx: usize) !void {
        var gltf_material = GltfMaterial{
            .name = try self.getMaterialName(ai_material, mat_idx),
        };

        if (self.verbose) {
            std.debug.print("  Processing material {d}: {s}\n", .{ mat_idx, gltf_material.name });
        }

        // Extract PBR properties
        try self.extractPbrProperties(ai_material, &gltf_material);

        // Extract textures from ASSIMP material properties only
        try self.extractTextures(ai_material, &gltf_material);

        // Note: Auto-discovery of textures has been disabled to prevent
        // unwanted texture assignments. Use addTexture() method for manual control.

        try self.materials.append(gltf_material);
    }

    fn getMaterialName(self: *MaterialProcessor, ai_material: *const assimp.aiMaterial, mat_idx: usize) ![]u8 {
        var ai_name = assimp.aiString{ .length = 0, .data = undefined };

        // Use the actual string key instead of macro
        const name_key = "$mat.name";
        const result = assimp.aiGetMaterialString(ai_material, name_key.ptr, 0, 0, &ai_name);

        if (result == assimp.aiReturn_SUCCESS and ai_name.length > 0) {
            const name_slice = ai_name.data[0..ai_name.length];
            return self.allocator.dupe(u8, name_slice);
        } else {
            // Generate default name
            return std.fmt.allocPrint(self.allocator, "material_{d}", .{mat_idx});
        }
    }

    fn extractPbrProperties(self: *MaterialProcessor, ai_material: *const assimp.aiMaterial, gltf_material: *GltfMaterial) !void {
        _ = self;

        // Extract base color with fallback to diffuse (following ASSIMP pattern)
        var base_color: assimp.aiColor4D = undefined;
        const base_color_key = "$clr.base";
        if (assimp.aiGetMaterialColor(ai_material, base_color_key.ptr, 0, 0, &base_color) == assimp.aiReturn_SUCCESS) {
            gltf_material.pbrMetallicRoughness.baseColorFactor[0] = base_color.r;
            gltf_material.pbrMetallicRoughness.baseColorFactor[1] = base_color.g;
            gltf_material.pbrMetallicRoughness.baseColorFactor[2] = base_color.b;
            gltf_material.pbrMetallicRoughness.baseColorFactor[3] = base_color.a;
        } else {
            // Fallback to diffuse color if base color not available
            var diffuse_color: assimp.aiColor4D = undefined;
            const diffuse_key = "$clr.diffuse";
            if (assimp.aiGetMaterialColor(ai_material, diffuse_key.ptr, 0, 0, &diffuse_color) == assimp.aiReturn_SUCCESS) {
                gltf_material.pbrMetallicRoughness.baseColorFactor[0] = diffuse_color.r;
                gltf_material.pbrMetallicRoughness.baseColorFactor[1] = diffuse_color.g;
                gltf_material.pbrMetallicRoughness.baseColorFactor[2] = diffuse_color.b;
                gltf_material.pbrMetallicRoughness.baseColorFactor[3] = diffuse_color.a;
            }
        }

        // Extract metallic factor with default fallback
        var metallic_factor: f32 = 0.0;
        const metallic_key = "$mat.metallicFactor";
        if (assimp.aiGetMaterialFloat(ai_material, metallic_key.ptr, 0, 0, &metallic_factor) == assimp.aiReturn_SUCCESS) {
            gltf_material.pbrMetallicRoughness.metallicFactor = metallic_factor;
        } else {
            // Default to non-metallic if not specified
            gltf_material.pbrMetallicRoughness.metallicFactor = 0.0;
        }

        // Extract roughness factor with sophisticated fallback (following ASSIMP pattern)
        var roughness_factor: f32 = DEFAULT_ROUGHNESS;
        const roughness_key = "$mat.roughnessFactor";
        if (assimp.aiGetMaterialFloat(ai_material, roughness_key.ptr, 0, 0, &roughness_factor) == assimp.aiReturn_SUCCESS) {
            gltf_material.pbrMetallicRoughness.roughnessFactor = roughness_factor;
        } else {
            // Try to derive from specular + shininess (ASSIMP conversion algorithm)
            var specular_color: assimp.aiColor4D = undefined;
            var shininess: f32 = 0.0;
            const specular_key = "$clr.specular";
            const shininess_key = "$mat.shininess";

            if (assimp.aiGetMaterialColor(ai_material, specular_key.ptr, 0, 0, &specular_color) == assimp.aiReturn_SUCCESS and
                assimp.aiGetMaterialFloat(ai_material, shininess_key.ptr, 0, 0, &shininess) == assimp.aiReturn_SUCCESS)
            {
                // Convert specular color to luminance using ITU-R BT.709 weights
                const specular_intensity = specular_color.r * LUMINANCE_RED_WEIGHT +
                    specular_color.g * LUMINANCE_GREEN_WEIGHT +
                    specular_color.b * LUMINANCE_BLUE_WEIGHT;
                // Normalize shininess with inverse exponential curve (ASSIMP algorithm)
                const normalized_shininess_raw = @sqrt(shininess / SHININESS_MAX_VALUE);
                const normalized_shininess = @max(0.0, @min(1.0, normalized_shininess_raw));
                // Low specular intensity should produce rough material even if shininess is high
                const final_shininess = normalized_shininess * specular_intensity;
                gltf_material.pbrMetallicRoughness.roughnessFactor = 1.0 - final_shininess;
            } else {
                // Default roughness if no conversion possible
                gltf_material.pbrMetallicRoughness.roughnessFactor = DEFAULT_ROUGHNESS;
            }
        }

        // Extract emissive color
        var emissive_color: assimp.aiColor4D = undefined;
        const emissive_key = "$clr.emissive";
        if (assimp.aiGetMaterialColor(ai_material, emissive_key.ptr, 0, 0, &emissive_color) == assimp.aiReturn_SUCCESS) {
            gltf_material.emissiveFactor[0] = emissive_color.r;
            gltf_material.emissiveFactor[1] = emissive_color.g;
            gltf_material.emissiveFactor[2] = emissive_color.b;
        }

        // Extract opacity and alpha mode
        var opacity: f32 = 1.0;
        const opacity_key = "$mat.opacity";
        if (assimp.aiGetMaterialFloat(ai_material, opacity_key.ptr, 0, 0, &opacity) == assimp.aiReturn_SUCCESS) {
            if (opacity < 1.0) {
                gltf_material.alphaMode = "BLEND";
                gltf_material.pbrMetallicRoughness.baseColorFactor[3] *= opacity;
            }
        }

        // Extract two-sided property
        var two_sided: i32 = 0;
        const two_sided_key = "$mat.twosided";
        if (assimp.aiGetMaterialInteger(ai_material, two_sided_key.ptr, 0, 0, &two_sided) == assimp.aiReturn_SUCCESS) {
            gltf_material.doubleSided = two_sided != 0;
        }

        // Extract alpha cutoff for MASK mode
        var alpha_cutoff: f32 = DEFAULT_ALPHA_CUTOFF;
        const alpha_cutoff_key = "$mat.gltf.alphaCutoff";
        if (assimp.aiGetMaterialFloat(ai_material, alpha_cutoff_key.ptr, 0, 0, &alpha_cutoff) == assimp.aiReturn_SUCCESS) {
            gltf_material.alphaCutoff = alpha_cutoff;
            if (gltf_material.alphaMode.len == 0 or std.mem.eql(u8, gltf_material.alphaMode, "OPAQUE")) {
                gltf_material.alphaMode = "MASK";
            }
        }
    }

    fn extractTextures(self: *MaterialProcessor, ai_material: *const assimp.aiMaterial, gltf_material: *GltfMaterial) !void {
        // Extract base color texture with fallback (following ASSIMP pattern)
        if (try self.extractTexture(ai_material, AI_TEXTURE_TYPE_BASE_COLOR, 0)) |texture_index| {
            gltf_material.pbrMetallicRoughness.baseColorTexture = GltfTextureInfo{ .index = texture_index };
        } else if (try self.extractTexture(ai_material, assimp.aiTextureType_DIFFUSE, 0)) |texture_index| {
            // Fallback to diffuse texture if no base color texture
            gltf_material.pbrMetallicRoughness.baseColorTexture = GltfTextureInfo{ .index = texture_index };
        }

        // Extract metallic-roughness texture with multiple fallbacks (following ASSIMP pattern)
        if (try self.extractTexture(ai_material, AI_TEXTURE_TYPE_DIFFUSE_ROUGHNESS, 0)) |texture_index| {
            gltf_material.pbrMetallicRoughness.metallicRoughnessTexture = GltfTextureInfo{ .index = texture_index };
        } else if (try self.extractTexture(ai_material, AI_TEXTURE_TYPE_METALNESS, 0)) |texture_index| {
            // Fallback to metalness texture
            gltf_material.pbrMetallicRoughness.metallicRoughnessTexture = GltfTextureInfo{ .index = texture_index };
        } else if (try self.extractTexture(ai_material, assimp.aiTextureType_SPECULAR, 0)) |texture_index| {
            // Last fallback to specular texture (for legacy materials)
            gltf_material.pbrMetallicRoughness.metallicRoughnessTexture = GltfTextureInfo{ .index = texture_index };
        }

        // Extract normal texture with height map fallback
        if (try self.extractTexture(ai_material, assimp.aiTextureType_NORMALS, 0)) |texture_index| {
            gltf_material.normalTexture = GltfNormalTextureInfo{ .index = texture_index };
        } else if (try self.extractTexture(ai_material, assimp.aiTextureType_HEIGHT, 0)) |texture_index| {
            // Height maps can be used as normal maps
            gltf_material.normalTexture = GltfNormalTextureInfo{ .index = texture_index };
        }

        // Extract occlusion texture (ASSIMP uses LIGHTMAP for ambient occlusion)
        if (try self.extractTexture(ai_material, assimp.aiTextureType_LIGHTMAP, 0)) |texture_index| {
            gltf_material.occlusionTexture = GltfOcclusionTextureInfo{ .index = texture_index };
        } else if (try self.extractTexture(ai_material, AI_TEXTURE_TYPE_AMBIENT_OCCLUSION, 0)) |texture_index| {
            // Direct ambient occlusion texture
            gltf_material.occlusionTexture = GltfOcclusionTextureInfo{ .index = texture_index };
        }

        // Extract emissive texture
        if (try self.extractTexture(ai_material, assimp.aiTextureType_EMISSIVE, 0)) |texture_index| {
            gltf_material.emissiveTexture = GltfTextureInfo{ .index = texture_index };
        }
    }

    fn extractTexture(self: *MaterialProcessor, ai_material: *const assimp.aiMaterial, texture_type: assimp.aiTextureType, index: u32) !?u32 {
        var path = assimp.aiString{ .length = 0, .data = undefined };

        const result = assimp.aiGetMaterialTexture(ai_material, texture_type, index, &path, null, // mapping
            null, // uvindex
            null, // blend
            null, // op
            null, // mapmode
            null // flags
        );

        if (result != assimp.aiReturn_SUCCESS or path.length == 0) {
            return null;
        }

        const texture_path = path.data[0..path.length];
        std.debug.print("    Found texture: {s}\n", .{texture_path});

        // Check if we already have this texture
        if (self.texture_path_map.get(texture_path)) |existing_index| {
            return existing_index;
        }

        // Create new image
        const image_index: u32 = @intCast(self.images.items.len);
        const image = GltfImage{
            .uri = try self.allocator.dupe(u8, texture_path),
            .name = try self.extractFileName(texture_path),
        };
        try self.images.append(image);

        // Create new texture
        const texture_index: u32 = @intCast(self.textures.items.len);
        const texture = GltfTexture{
            .source = image_index,
            .sampler = 0, // Use default sampler
        };
        try self.textures.append(texture);

        // Map path to texture index
        const path_copy = try self.allocator.dupe(u8, texture_path);
        try self.texture_path_map.put(path_copy, texture_index);

        return texture_index;
    }

    fn extractFileName(self: *MaterialProcessor, path: []const u8) !?[]u8 {
        const basename = std.fs.path.basename(path);
        if (basename.len > 0) {
            return try self.allocator.dupe(u8, basename); // zlint-disable no-return-try -- needed for optional
        }
        return null;
    }

    fn makeRelativePath(self: *MaterialProcessor, absolute_texture_path: []const u8) ![]u8 {
        // Get the directory of the output glTF file
        const output_dir = std.fs.path.dirname(self.output_path) orelse ".";

        // Try to make the texture path relative to the output directory
        if (std.fs.path.relative(self.allocator, output_dir, absolute_texture_path)) |relative_path| {
            return relative_path;
        } else |_| {
            // If making relative path fails, just use the filename
            const filename = std.fs.path.basename(absolute_texture_path);
            return self.allocator.dupe(u8, filename);
        }
    }

    fn autoDiscoverTextures(self: *MaterialProcessor, gltf_material: *GltfMaterial) !void {
        // Get the directory containing the input file
        const input_dir = std.fs.path.dirname(self.input_path) orelse ".";

        // Common texture directory names to search (both in same dir and parent dir)
        const texture_dirs = [_][]const u8{ "textures", "Textures", "texture", "tex", "../textures", "../Textures", "../texture", "../tex" };

        for (texture_dirs) |tex_dir| {
            const full_tex_path = try std.fs.path.join(self.allocator, &[_][]const u8{ input_dir, tex_dir });
            defer self.allocator.free(full_tex_path);

            // Try to open the texture directory
            var dir = std.fs.cwd().openDir(full_tex_path, .{ .iterate = true }) catch {
                continue;
            };
            defer dir.close();

            var textures_found: u32 = 0;

            // Iterate through files in the texture directory
            var walker = dir.iterate();
            while (walker.next() catch null) |entry| {
                if (entry.kind != .file) continue;

                const filename = entry.name;

                // Check for common texture naming patterns
                if (self.isTextureType(filename, "basecolor") or
                    self.isTextureType(filename, "diffuse") or
                    self.isTextureType(filename, "_d"))
                {
                    const texture_path = try std.fs.path.join(self.allocator, &[_][]const u8{ full_tex_path, filename });
                    defer self.allocator.free(texture_path);

                    if (try self.createTextureFromPath(texture_path)) |texture_index| {
                        gltf_material.pbrMetallicRoughness.baseColorTexture = GltfTextureInfo{ .index = texture_index };
                        textures_found += 1;
                    }
                }

                if (self.isTextureType(filename, "normal") or
                    self.isTextureType(filename, "nrm") or
                    self.isTextureType(filename, "_NRM"))
                {
                    const texture_path = try std.fs.path.join(self.allocator, &[_][]const u8{ full_tex_path, filename });
                    defer self.allocator.free(texture_path);

                    if (try self.createTextureFromPath(texture_path)) |texture_index| {
                        gltf_material.normalTexture = GltfNormalTextureInfo{ .index = texture_index };
                        textures_found += 1;
                    }
                }

                if (self.isTextureType(filename, "metallic") or
                    self.isTextureType(filename, "_M"))
                {
                    const texture_path = try std.fs.path.join(self.allocator, &[_][]const u8{ full_tex_path, filename });
                    defer self.allocator.free(texture_path);

                    if (try self.createTextureFromPath(texture_path)) |texture_index| {
                        gltf_material.pbrMetallicRoughness.metallicRoughnessTexture = GltfTextureInfo{ .index = texture_index };
                        textures_found += 1;
                    }
                }
            }

            // If we found textures in this directory, report and exit
            if (textures_found > 0) {
                std.debug.print("    Auto-discovered {} textures in: {s}\n", .{ textures_found, tex_dir });
                break;
            }
        }
    }

    fn isTextureType(self: *MaterialProcessor, filename: []const u8, texture_type: []const u8) bool {
        // Allocate buffer for lowercase filename
        const lower_filename = self.allocator.alloc(u8, filename.len) catch return false;
        defer self.allocator.free(lower_filename);

        // Convert filename to lowercase for case-insensitive comparison
        _ = std.ascii.lowerString(lower_filename, filename);

        return std.mem.indexOf(u8, lower_filename, texture_type) != null;
    }

    fn createTextureFromPath(self: *MaterialProcessor, texture_path: []const u8) !?u32 {
        // Check if we already have this texture
        if (self.texture_path_map.get(texture_path)) |existing_index| {
            return existing_index;
        }

        // Convert absolute texture path to relative path from output glTF file
        const relative_path = try self.makeRelativePath(texture_path);
        defer self.allocator.free(relative_path);

        // Create new image
        const image_index: u32 = @intCast(self.images.items.len);
        const image = GltfImage{
            .uri = try self.allocator.dupe(u8, relative_path),
            .name = try self.extractFileName(texture_path),
        };
        try self.images.append(image);

        // Create new texture
        const texture_index: u32 = @intCast(self.textures.items.len);
        const texture = GltfTexture{
            .source = image_index,
            .sampler = 0, // Use default sampler
        };
        try self.textures.append(texture);

        // Map path to texture index
        const path_copy = try self.allocator.dupe(u8, texture_path);
        try self.texture_path_map.put(path_copy, texture_index);

        return texture_index;
    }

    pub fn getMaterialIndexForMesh(self: *MaterialProcessor, ai_mesh: *const assimp.aiMesh) ?u32 {
        if (ai_mesh.mMaterialIndex < self.materials.items.len) {
            return @intCast(ai_mesh.mMaterialIndex);
        }
        return null;
    }

    // Manual texture assignment (replaces auto-discovery for explicit control)
    pub fn addTexture(self: *MaterialProcessor, material_index: u32, texture_type: []const u8, texture_path: []const u8) !void {
        if (material_index >= self.materials.items.len) {
            std.debug.print("Warning: Material index {d} out of range (max: {d})\n", .{ material_index, self.materials.items.len - 1 });
            return;
        }

        const texture_index = try self.createTextureFromPath(texture_path) orelse {
            std.debug.print("Warning: Failed to create texture from path: {s}\n", .{texture_path});
            return;
        };

        var material = &self.materials.items[material_index];

        if (std.mem.eql(u8, texture_type, "basecolor") or std.mem.eql(u8, texture_type, "diffuse")) {
            material.pbrMetallicRoughness.baseColorTexture = GltfTextureInfo{ .index = texture_index };
            std.debug.print("  Added base color texture to material {d}: {s}\n", .{ material_index, texture_path });
        } else if (std.mem.eql(u8, texture_type, "normal")) {
            material.normalTexture = GltfNormalTextureInfo{ .index = texture_index };
            std.debug.print("  Added normal texture to material {d}: {s}\n", .{ material_index, texture_path });
        } else if (std.mem.eql(u8, texture_type, "metallic") or std.mem.eql(u8, texture_type, "roughness")) {
            material.pbrMetallicRoughness.metallicRoughnessTexture = GltfTextureInfo{ .index = texture_index };
            std.debug.print("  Added metallic/roughness texture to material {d}: {s}\n", .{ material_index, texture_path });
        } else if (std.mem.eql(u8, texture_type, "emissive")) {
            material.emissiveTexture = GltfTextureInfo{ .index = texture_index };
            std.debug.print("  Added emissive texture to material {d}: {s}\n", .{ material_index, texture_path });
        } else {
            std.debug.print("Warning: Unknown texture type '{s}', ignoring\n", .{texture_type});
        }
    }
};
