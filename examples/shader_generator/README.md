# Shader Composition System for Zig/OpenGL

This document shows the architecture and example outputs of the shader composition system.

## Directory Structure

```
your_engine/
├── shader_compose/
│   ├── shader_compose.zig    # Core library
│   ├── build.zig
│   └── modules/
│       ├── transforms/
│       │   └── standard.module
│       ├── animation/
│       │   └── skeletal.module
│       ├── sampling/
│       │   └── texture.module
│       ├── material/
│       │   └── pbr_maps.module
│       ├── lighting/
│       │   └── pbr.module
│       └── output/
│           ├── standard.module
│           └── hdr.module
```

## Module Format

Each `.module` file has header directives followed by GLSL code:

```glsl
//! stage: fragment
//! requires: vec3 world_normal, vec3 view_dir
//! provides: vec3 lit_color
//! uniform: sampler2D some_texture binding=5
//! block: MyUniforms binding=2 { mat4 transform; vec3 color; }

void module_name() {
    // Your GLSL code here
    // Can read any 'requires' variables
    // Must write to 'provides' variables
}
```

## Recipe Definition

In your Zig code, you define shader recipes:

```zig
const pbr_recipe = ShaderRecipe{
    .name = "pbr_standard",
    .vertex_modules = &.{"transforms/standard"},
    .fragment_modules = &.{
        "sampling/texture",
        "material/pbr_maps", 
        "lighting/pbr",
        "output/hdr",
    },
    .vertex_inputs = &.{
        .{ .name = "position", .type = .vec3, .location = 0 },
        .{ .name = "normal", .type = .vec3, .location = 1 },
        .{ .name = "uv", .type = .vec2, .location = 2 },
    },
    .vertex_outputs = &.{
        .{ .name = "world_position", .type = .vec3 },
        .{ .name = "world_normal", .type = .vec3 },
        .{ .name = "frag_uv", .type = .vec2 },
    },
    .uniform_blocks = &.{
        .{
            .name = "Transforms",
            .binding = 0,
            .members = &.{
                .{ .name = "model", .type = .mat4 },
                .{ .name = "view_projection", .type = .mat4 },
            },
        },
    },
};
```

---

## Example Generated Output

Given the recipe above, here's what the generator produces:

### Generated Vertex Shader (pbr_standard.vert)

```glsl
#version 450

#define MAX_LIGHTS 4

// Vertex Inputs
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 uv;

// Varyings
layout(location = 0) out vec3 world_position;
layout(location = 1) out vec3 world_normal;
layout(location = 2) out vec2 frag_uv;

// Uniform Blocks
layout(std140, binding = 0) uniform Transforms {
    mat4 model;
    mat4 view_projection;
};

// Module variables
vec4 gl_Position;

// --- Module: transforms/standard ---
void transforms_standard() {
    world_position = (model * vec4(position, 1.0)).xyz;
    world_normal = normalize(mat3(transpose(inverse(model))) * normal);
    frag_uv = uv;
    gl_Position = view_projection * vec4(world_position, 1.0);
}

void main() {
    transforms_standard();
}
```

### Generated Fragment Shader (pbr_standard.frag)

```glsl
#version 450

#define MAX_LIGHTS 4

// Varyings
layout(location = 0) in vec3 world_position;
layout(location = 1) in vec3 world_normal;
layout(location = 2) in vec2 frag_uv;

// Fragment Outputs
layout(location = 0) out vec4 frag_color;

// Uniform Blocks
layout(std140, binding = 0) uniform Transforms {
    mat4 model;
    mat4 view_projection;
};

layout(std140, binding = 1) uniform Lighting {
    vec3 camera_pos;
    vec3 light_dir;
    vec3 light_color;
    float ambient_strength;
};

layout(std140, binding = 3) uniform Tonemapping {
    float exposure;
    float gamma;
};

// Uniforms
layout(binding = 0) uniform sampler2D albedo_map;
layout(binding = 1) uniform sampler2D metallic_roughness_map;
layout(binding = 2) uniform sampler2D ao_map;
layout(binding = 4) uniform samplerCube irradiance_map;
layout(binding = 5) uniform samplerCube prefilter_map;
layout(binding = 6) uniform sampler2D brdf_lut;

// Module variables
vec4 base_color;
float alpha;
float metallic;
float roughness;
float ao;
vec3 lit_color;
vec4 final_color;

// --- Module: sampling/texture ---
void sampling_texture() {
    vec4 sampled = texture(albedo_map, frag_uv);
    base_color = sampled;
    alpha = sampled.a;
}

// --- Module: material/pbr_maps ---
void material_pbr_maps() {
    vec4 mr = texture(metallic_roughness_map, frag_uv);
    metallic = mr.b;
    roughness = mr.g;
    ao = texture(ao_map, frag_uv).r;
}

// --- Module: lighting/pbr ---
const float PI = 3.14159265359;

float distribution_ggx(vec3 N, vec3 H, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;
    
    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
    
    return num / denom;
}

float geometry_schlick_ggx(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometry_smith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return geometry_schlick_ggx(NdotV, roughness) * geometry_schlick_ggx(NdotL, roughness);
}

vec3 fresnel_schlick(float cos_theta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

void lighting_pbr() {
    vec3 N = normalize(world_normal);
    vec3 V = normalize(camera_pos - world_position);
    vec3 L = normalize(-light_dir);
    vec3 H = normalize(V + L);
    
    vec3 albedo = base_color.rgb;
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    
    float NDF = distribution_ggx(N, H, roughness);
    float G = geometry_smith(N, V, L, roughness);
    vec3 F = fresnel_schlick(max(dot(H, V), 0.0), F0);
    
    vec3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    vec3 specular = numerator / denominator;
    
    vec3 kS = F;
    vec3 kD = (vec3(1.0) - kS) * (1.0 - metallic);
    
    float NdotL = max(dot(N, L), 0.0);
    
    vec3 ambient = ambient_strength * albedo * ao;
    lit_color = ambient + (kD * albedo / PI + specular) * light_color * NdotL;
}

// --- Module: output/hdr ---
vec3 aces_tonemap(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void output_hdr() {
    vec3 mapped = lit_color * exposure;
    mapped = aces_tonemap(mapped);
    mapped = pow(mapped, vec3(1.0 / gamma));
    final_color = vec4(mapped, alpha);
}

void main() {
    sampling_texture();
    material_pbr_maps();
    lighting_pbr();
    output_hdr();
    frag_color = final_color;
}
```

---

## Key Benefits

### 1. Single Source of Truth for Bindings

Change vertex attribute locations in ONE place:

```zig
.vertex_inputs = &.{
    .{ .name = "position", .type = .vec3, .location = 0 },
    .{ .name = "normal", .type = .vec3, .location = 1 },
    .{ .name = "uv", .type = .vec2, .location = 2 },
    // Add tangent? Just add here, all shaders regenerate correctly
    .{ .name = "tangent", .type = .vec4, .location = 3 },
},
```

### 2. Easy Shader Variants

```zig
fn createVariants(base: ShaderRecipe) []GeneratedShader {
    var variants = ArrayList(GeneratedShader).init(allocator);
    
    // With/without HDR
    for ([_][]const u8{ "output/standard", "output/hdr" }) |output_module| {
        var recipe = base;
        recipe.fragment_modules = base.fragment_modules[0..3] ++ &.{output_module};
        variants.append(generator.generate(recipe));
    }
    
    // With/without skeletal animation
    // ...
    
    return variants.toOwnedSlice();
}
```

### 3. Validation at Build Time

The generator validates the dataflow graph:
- Every module's `requires` must be satisfied by a previous module's `provides`
- Type mismatches are caught before shader compilation
- Missing outputs are flagged

### 4. Modular Testing

Test individual modules in isolation:

```zig
test "pbr lighting produces lit_color" {
    const module = generator.loadModule("lighting/pbr");
    try expect(hasProvides(module, "lit_color", .vec3));
    try expect(hasRequires(module, "world_normal", .vec3));
}
```

---

## Integration with Your Engine

### Compile-Time Generation (Recommended)

```zig
// In build.zig
const gen_step = b.addSystemCommand(&.{ "zig", "run", "tools/generate_shaders.zig" });
exe.step.dependOn(&gen_step.step);
```

### Runtime Generation (Development)

```zig
pub fn reloadShader(self: *Renderer, name: []const u8) !void {
    const recipe = self.recipes.get(name) orelse return error.UnknownShader;
    const generated = try self.generator.generate(recipe);
    
    // Compile with OpenGL
    const program = try self.gl.compileProgram(
        generated.vertex_source,
        generated.fragment_source,
    );
    
    self.shaders.put(name, program);
}
```

### Hot Reload

Watch `.module` files and regenerate on change:

```zig
fn watchModules(self: *ShaderSystem) void {
    while (true) {
        const event = self.watcher.wait();
        if (std.mem.endsWith(u8, event.path, ".module")) {
            self.generator.invalidateModule(event.path);
            self.regenerateAffectedShaders();
        }
    }
}
```

---

## Extending the System

### Custom Directives

Add your own module directives:

```glsl
//! feature: NORMAL_MAPPING
//! feature: PARALLAX_OCCLUSION
```

```zig
// Generator checks features and emits #ifdef blocks
if (module.hasFeature("NORMAL_MAPPING")) {
    try writer.writeAll("#ifdef NORMAL_MAPPING\n");
    // ...
}
```

### Include Dependencies

```glsl
//! include: math/common
//! include: noise/simplex
```

### Conditional Compilation

```zig
.defines = &.{
    .{ .name = "SHADOW_CASCADES", .value = "4" },
    .{ .name = "USE_NORMAL_MAPS" },  // No value = just defined
},
```
