# redfish_gl_zig - 3D Graphics Engine

## Project Overview

**redfish_gl_zig** is a 3D graphics engine written in Zig focused on real-time rendering of animated glTF models with physically-based rendering (PBR). The engine supports character animation, texturing, lighting, and camera controls.

### Current Status (2025-08-19)
- ✅ **Production-Ready 3D Engine** - Complete foundation with PBR rendering pipeline
- ✅ **Core Rendering**: OpenGL 4.0 pipeline with Cook-Torrance PBR shaders
- ✅ **Native glTF System** - Complete glTF 2.0 support with skeletal animation
- ✅ **Cubic Spline Animation** - glTF-compliant Hermite interpolation system
- ✅ **Enhanced Animation Blending** - WeightedAnimation system with precision controls
- ✅ **Multi-Game Architecture** - Successfully supports multiple game projects
- ✅ **Game Projects**: angrybot (fully migrated), level_01 (active development)
- ✅ **Movement System** - Precision-preserved movement with enhanced performance
- ✅ **Development Tools**: Comprehensive debugging, profiling, and shader validation
- ✅ **Foundation Plans Completed**: Plans 001-003 (GLB, Demo, PBR Shaders)
- 🎯 **Current Phase**: Advanced game development and engine feature expansion

### Architecture

```
src/
├── core/           # Core engine systems
│   ├── gltf/      # glTF parsing and model loading
│   ├── shapes/    # Primitive geometry generators
│   ├── movement.zig # Enhanced movement system with precision preservation
│   └── utils/     # Utility functions
└── math/          # Custom math library (Vec2/3/4, Mat4, etc.)

examples/
└── demo_app/      # Main demo application with PBR shaders

games/             # Game projects using the engine
├── angrybot/      # Fully migrated 3D shooter game
└── level_01/      # Active game development project

libs/              # Third-party dependencies
├── zglfw/         # GLFW windowing
├── zopengl/       # OpenGL bindings
├── zgui/          # Dear ImGui
├── zstbi/         # Image loading
└── miniaudio/     # Audio support
```

### Key Components

#### Graphics Pipeline
- **Renderer**: OpenGL 4.0 core profile
- **Shaders**: Vertex/fragment shaders for PBR materials
- **Textures**: Support for diffuse, specular, emissive, and normal maps
- **Camera**: Free-look camera with movement controls

#### Animation System (`src/core/animator.zig`)
- **AnimationClip**: glTF animation references with time-based repeat modes
- **Skeletal Animation**: Complete glTF skin/joint system with inverse bind matrices
- **Cubic Spline Interpolation**: glTF-compliant Hermite interpolation for smooth animation curves
- **Linear Interpolation**: Standard Vec3 linear and quaternion spherical (slerp) interpolation
- **WeightedAnimation**: Enhanced multi-animation blending with precision controls
- **playWeightAnimations**: Sophisticated animation mixing for complex character movement
- **Usage**: `model.playWeightAnimations(&weight_animations, frame_time)` for directional character animation

#### Math Library (`src/math/`)
- Custom Zig implementations with column-major matrix conventions
- Types: `Vec2`, `Vec3`, `Vec4`, `Mat4`, `Quat`
- Functions: Transformations, projections, ray casting
- **Column-major storage**: Compatible with OpenGL and CGLM conventions
- **Matrix documentation**: Clear data layout and indexing conventions
- If there is missing needed functionality, propose adding it

#### glTF Development Tools (`src/core/gltf/`)
- **Report System**: Comprehensive glTF inspection and analysis with detailed animation keyframes and skin data
- **Usage**: Console output, string generation, file export (markdown format)
- **Analysis**: Scenes, meshes, accessors, animations (with keyframe data), materials, textures, skins (with inverse bind matrices)
- **Integration**: Available as `@import("core").gltf_report`
- **Detailed Features**: Human-readable animation keyframes, skeletal joint hierarchies, inverse bind matrix data
- **Configuration**: Flag-based control with parameterized output limits for debugging

#### Screenshot & Debug System (`examples/demo_app/screenshot*.zig` & `src/core/shader.zig`)
- **F12 Screenshot Capture**: Framebuffer-based PNG screenshots with automatic directory creation
- **Synchronized Shader Debug**: JSON-formatted uniform dumps with timestamp correlation
- **Enhanced Shader API**: `dumpDebugUniformsJSON()`, `saveDebugUniforms()` methods in core shader system
- **Output Location**: `/tmp/redfish_screenshots/` with format `YYYY-MM-DD_HH.MM.SS.mmm_pbr_{screenshot|uniforms}.{png|json}`
- **Usage**: Press F12 during demo_app runtime for coordinated capture of visuals and shader state

#### Asset Loading System (`src/core/asset_loader.zig`)
- **ASSIMP-Style Configuration**: Set loading options before calling `buildModel()`
- **Normal Generation Modes**: `skip` (shader fallback), `simple` (upward normals), `accurate` (calculated from geometry)
- **Centralized Preprocessing**: Normal generation happens at asset level, not during mesh creation
- **Usage Pattern**: `gltf_asset.setNormalGenerationMode(.accurate)` before `buildModel()`
- **Automatic Detection**: Only generates normals for mesh primitives that lack them
- **Memory Management**: Pre-generated normals stored in HashMap with composite keys

#### Enhanced Movement System (`src/core/movement.zig`)
- **Precision Preservation**: Enhanced movement calculations with improved numerical precision
- **Performance Optimized**: Refactored for better performance in game scenarios
- **Type Safety**: Improved data structures with better performance and type safety
- **Game Integration**: Seamlessly integrated into angrybot and level_01 game projects

## Coding Style Guidelines

### General Principles

#### Write Idiomatic Zig
- Follow Zig conventions and idioms
- Use Zig's built-in language features appropriately
- Prefer Zig standard library patterns

#### Code for Clarity
- Write clear, readable code that expresses intent
- Choose descriptive variable and function names
- Structure code logically

#### Avoid Clever Code
- Prioritize readability over brevity
- Avoid obscure tricks or overly complex expressions
- Write code that other developers can easily understand

#### Function Parameters
- Avoid calling complex functions within function parameters
- Break down complex expressions into intermediate variables when it improves readability
- Exception: Simple field access is acceptable (see Variable Declarations below)

### Variable Declarations

#### Inline Field Access
Use inline field access in function calls instead of creating intermediate variables for simple cases:

**Preferred:**
```zig
const nodes = try allocator.alloc(gltf_types.Node, nodes_json.array.items.len);
```

**Avoid:**
```zig
const node_count = nodes_json.array.items.len;
const nodes = try allocator.alloc(gltf_types.Node, node_count);
```

This applies to scenarios where referencing nested fields directly in function calls is acceptable and improves code conciseness without sacrificing clarity.

## Project-Specific Guidelines

### Commit Guidelines
- NEVER add a signature at the end of commit messages

### Math Operations
- Use the math types and functions under `src/math/` when possible
- Prefer project-specific math implementations over external libraries
- This helps maintain consistency and reduces dependencies

### Model Loading
- glTF models should be loaded through `GltfAsset` in `src/core/asset_loader.zig`
- Textures are cached and managed centrally
- Use descriptive material names for texture associations

### Animation (glTF Native)
- **AnimationClip**: Reference glTF animations by index with `AnimationClip.init(animation_index, end_time, repeat_mode)`
- **Time-based**: Uses seconds instead of ticks for precise timing control
- **API Preserved**: All existing methods work unchanged (`playClip()`, `playTick()`, `updateAnimation()`)
- **Keyframe Support**: Linear interpolation for Vec3, spherical interpolation (slerp) for quaternions
- **Shader Integration**: Uses proper glTF terminology with `jointMatrices[100]` array for vertex shaders

### Error Handling
- Use Zig's error unions for fallible operations
- Prefer explicit error handling over assertions
- Log errors with context using `std.debug.print()`

## Build & Development

### Building

#### Recommended Workflow (using just)
```bash
# Development with auto-rebuild
just dev

# Quick build and run
just run

# Build specific game projects
zig build angrybot-run
zig build level_01-run

# Run all tests
just test

# Check compilation
just check
```

#### Direct Zig Commands
```bash
# Build main example
zig build demo_app

# Run main example  
zig build demo_app-run

# Check compilation
zig build check

# Run tests
zig build test-movement
```

#### Development Tools
```bash
# Project statistics
just stats

# Performance benchmarks
just bench-build

# Validate shaders
just validate-shaders

# Environment check
just doctor
```

### Dependencies
- **zglfw**: Window management and input
- **zopengl**: OpenGL function loading
- **zgui**: Immediate mode GUI
- **zstbi**: Image loading
- **cglm**: C math library (present but unused - prefer local math library)
- **miniaudio**: Audio playback support

## Future Development Areas

### Potential Enhancements
- **Scene Management**: Multi-model scene support with spatial organization
- **Advanced Lighting**: Shadow mapping, environment mapping, multi-light support
- **Performance**: Animation data caching, keyframe lookup optimization  
- **Audio Integration**: 3D positional audio and ambient sound support
- **Serialization**: Scene and game state serialization systems

## Current Active Plans

See `plan/active-plans.md` for detailed project roadmap.

**Current Focus**: Advanced game development and engine feature expansion beyond foundation plans

## Recent Changes

See [CHANGELOG.md](CHANGELOG.md) for detailed project history and recent updates.

### Development Notes
- **Active demo**: `examples/demo_app/main.zig` (build target: `demo_app`)
- **Shaders**: Located in `examples/demo_app/shaders/`
- **Math Library**: Pure Zig implementation in `src/math/` - add missing functions here
- **Asset Loading**: Use `GltfAsset` from `src/core/asset_loader.zig` for all model loading
- **glTF Analysis**: Use `core.gltf_report.GltfReport` for model inspection and debugging
- **Development Workflow**: Use `just dev` for auto-rebuild, specific game builds for focused development
- **Complete Guide**: See `DEVELOPMENT.md` for comprehensive workflow documentation
- **Watch Scripts**: Use `./scripts/watch-*.sh` for specialized development modes

## Coding Memories
- **NEVER add signatures to commit messages**
- When adding a large list of items within {} put a comma after that last item so that the zig formatter will fold the line nicely
- When writing an if else statement always include {}
- When using a pattern like self.arena.allocator(), I prefer calling it once to set a local variable at the top of the function then using the local variable instead of making multiple function calls. It reduces the clutter and makes the code easier to read.
- **Animation System Architecture**: When replacing complex legacy systems (like ASSIMP), maintain API compatibility by keeping the same public interfaces while completely rewriting the internal implementation. This allows existing code to work unchanged while modernizing the underlying technology.
- **Type Import Patterns**: Always import types at the top of files rather than using inline `@import()` in function parameters. This improves readability and makes dependencies explicit.
- **Wrapper Struct Avoidance**: Avoid unnecessary wrapper structs that just hold references to other data. Direct references are cleaner and reduce cognitive overhead (e.g., `gltf_asset: *const GltfAsset` vs `gltf_asset_ref: GltfAssetRef`).
- **Code Organization**: When refactoring, prefer moving functionality to appropriate modules over creating new structures. Extract functions cleanly from domain-specific modules to general-purpose ones.
- **Documentation Standards**: Add comprehensive struct documentation when dealing with complex conventions (e.g., matrix storage formats, coordinate systems).

## Advanced Features

### Cubic Spline Animation System
- **glTF Compliance**: Full implementation of glTF CUBICSPLINE interpolation mode
- **Hermite Basis**: Standard cubic Hermite basis functions matching Khronos reference
- **Smooth Animation**: Eliminates jerky transitions with continuous velocity and acceleration
- **Type-Safe Dispatch**: Union-based architecture for compile-time interpolation selection
- **Data Structures**: `Vec3CubicKeyframe`, `QuatCubicKeyframe` with in_tangent/value/out_tangent fields

### Enhanced Animation Blending
- **WeightedAnimation**: Sophisticated multi-animation blending with precision controls
- **playWeightAnimations()**: Handles complex character movement with weight-based mixing
- **Quaternion Normalization**: Proper blending mathematics for smooth rotational transitions
- **Game Integration**: Successfully integrated into angrybot character animation system
- Zig std.debug.print always requires args, for example std.debug.print("hello", .{})