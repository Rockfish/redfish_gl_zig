# redfish_gl_zig - 3D Graphics Engine

## Project Overview

**redfish_gl_zig** is a 3D graphics engine written in Zig focused on real-time rendering of animated glTF models with physically-based rendering (PBR). The engine supports character animation, texturing, lighting, and camera controls.

### Current Status (2025-07-12)
- ✅ Core rendering pipeline with OpenGL 4.0
- ✅ Architecture refactoring completed (commit 6725b17)
- ✅ Format-agnostic rendering components (Model, Mesh, Animator)
- ✅ **Native glTF Animation System** - Complete ASSIMP replacement with glTF-native implementation
- ✅ **Skeletal Animation System** - Fully functional with Fox, Cesium Man, and mixed model support
- ✅ PBR material support (diffuse, specular, emissive, normals)
- ✅ Camera controls (WASD movement + mouse look)
- ✅ Custom math library integration with column-major matrix fixes
- ✅ **Completed**: Plan 001 - GLB Support (completed 2024-06-26)
- ✅ **Completed**: Plan 002 - Demo Application (fully completed 2025-07-04)
- ✅ **Major Milestone**: Complete Skeletal Animation Implementation
- ✅ **Enhanced UI**: Model statistics display with comprehensive runtime metrics
- ✅ **glTF Development Tools**: Comprehensive glTF inspection and reporting system with detailed animation keyframes and skin data (2025-07-13)
- ✅ **Professional Development Workflow**: Automated build, test, and shader validation tools
- ✅ **Screenshot & Debug System**: F12 framebuffer screenshots with synchronized shader uniform dumps (2025-07-06)
- ✅ **ASSIMP-Style Asset Loading Options** - Configurable normal generation with skip/simple/accurate modes (2025-07-08)
- ✅ **ASSIMP to glTF Migration System** - Complete custom texture assignment system for porting ASSIMP projects (2025-07-11)
- ✅ **Animation Blending System** - WeightedAnimation implementation with playWeightAnimations for complex character animation (2025-07-12)
- ✅ **game_angrybot Player Port** - Complete modernization from ASSIMP to glTF system maintaining animation blending (2025-07-12)
- 🚧 **Active**: Continue porting game_angrybot components (enemy.zig, bullets.zig, etc.)
- 📋 Next: Complete remaining game_angrybot components, then Plan 003 - Basic PBR Shaders

### Architecture

```
src/
├── core/           # Core engine systems
│   ├── gltf/      # glTF parsing and model loading
│   ├── shapes/    # Primitive geometry generators
│   └── utils/     # Utility functions
└── math/          # Custom math library (Vec2/3/4, Mat4, etc.)

examples/
└── demo_app/      # main demo application using core/gltf

libs/              # Third-party dependencies
├── zglfw/         # GLFW windowing
├── zopengl/       # OpenGL bindings
├── zgui/          # Dear ImGui
├── zstbi/         # Image loading
├── cglm/          # C math library - for reference
└── miniaudio/     # Audio support
```

### Key Components

#### Graphics Pipeline
- **Renderer**: OpenGL 4.0 core profile
- **Shaders**: Vertex/fragment shaders for PBR materials
- **Textures**: Support for diffuse, specular, emissive, and normal maps
- **Camera**: Free-look camera with movement controls

#### Animation System (glTF Native)
- **AnimationClip**: glTF animation references with time-based repeat modes
- **Animator**: Native glTF animation playback with keyframe interpolation
- **Joints**: Skeletal animation using glTF skin/joint system with inverse bind matrices
- **Interpolation**: Linear Vec3 and spherical quaternion interpolation
- **API Compatibility**: Maintains all existing interfaces for seamless mini-game integration

#### Animation Blending System (`src/core/animator.zig`)
- **WeightedAnimation**: Multi-animation blending with weight, timing, and offset control
- **playWeightAnimations**: Simultaneous animation mixing for complex character movement
- **Frame-to-Time Conversion**: Automatic conversion from ASSIMP frame-based to glTF time-based animation
- **Weight Normalization**: Proper blending mathematics with quaternion renormalization
- **ASSIMP Compatibility**: Maintains same blending behavior as original game_angrybot system
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

#### ASSIMP to glTF Migration System (`src/core/asset_loader.zig`)
- **Custom Texture Assignment**: Manual texture assignment for models without material definitions
- **API Bridge**: ASSIMP texture-type approach ↔ glTF uniform-name approach for maximum flexibility
- **TextureConfig**: Comprehensive texture settings (filter, wrap, flip_v, gamma_correction)
- **Usage Pattern**: `gltf_asset.addTexture("MeshName", "texture_diffuse", "path.tga", config)`
- **Override System**: Custom textures override material textures with priority control
- **Memory Management**: Arena-based allocation with texture caching and proper GL cleanup
- **Critical for Porting**: Enables seamless migration of ASSIMP-based games to glTF architecture

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

# Shader development (Plan 003)
just pbr-dev

# Quick build and run
just run

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

## Known Issues & TODOs

### Current Issues
- Memory management needs review in texture cache cleanup
- Animation blending not yet implemented (future enhancement)
- Single model rendering only (no scene graph)

### Next Steps
1. **Mini-Game Integration** 
   - Port existing mini-game code to use new glTF animation system
   - Test API compatibility and performance with game-specific animation patterns
   - Verify skeletal animation works correctly with character controllers

2. **Animation System Enhancements**
   - Implement animation blending and transitions between clips
   - Add support for morph target animations (weights)
   - Optimize keyframe lookup with binary search for large animations

3. **Performance Optimization**
   - Optimize keyframe lookup with binary search for large animations
   - Implement animation data caching for frequently used clips
   - Profile memory usage and optimize joint matrix calculations

4. **Future enhancements**:
   - Implement animation blending and transitions between clips
   - Add support for multiple models in a scene
   - Implement shadow mapping for better lighting
   - Add audio integration for ambient sounds
   - Create scene serialization system

## Current Active Plans

See `plan/active-plans.md` for detailed project roadmap.

**Current Focus**: Plan 003 - Shader Improvements (Basic PBR rendering and materials)

## Recent Changes

See [CHANGELOG.md](CHANGELOG.md) for detailed project history and recent updates.

### Development Notes
- **Active demo**: `examples/demo_app/main.zig` (build target: `demo_app`)
- **Shaders**: Located in `examples/demo_app/shaders/`
- **Math Library**: Pure Zig implementation in `src/math/` - add missing functions here
- **Asset Loading**: Use `GltfAsset` from `src/core/asset_loader.zig` for all model loading
- **glTF Analysis**: Use `core.gltf_report.GltfReport` for model inspection and debugging
- **Development Workflow**: Use `just dev` for auto-rebuild, `just pbr-dev` for shader work
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

## ASSIMP→glTF Migration Rules

### Core Principle: REWRITE, DON'T WRAP
- **Rule**: Modernize legacy code to use glTF patterns during migration, never create compatibility layers
- **Why**: Reduces complexity, improves maintainability, leverages glTF improvements
- **GltfAsset ≡ ModelBuilder**: Equivalent functionality, better API - always use GltfAsset

### Decision Tree for Migration
1. **Equivalent exists?** → Rewrite calls to use modern glTF API
2. **Core missing functionality?** → Implement new (e.g., playWeightAnimations)  
3. **Just API differences?** → Always rewrite, never wrap

### Migration Patterns (Apply These)
```zig
// ModelBuilder.init() → GltfAsset.init()
// addTexture(mesh, texture_diffuse, path) → addTexture(mesh, "texture_diffuse", path, config)
// .fbx/.dae paths → .gltf paths
// Keep: playWeightAnimations() (genuinely new functionality)
```

### Red Flags (Avoid These)
- Creating ModelBuilder wrapper struct around GltfAsset
- Enum→string conversion utilities for textures
- Any "compatibility layer" thinking
- Maintaining multiple APIs for same functionality
- TextureType enum instead of string uniform names

### Implementation Memory
- **ASSIMP Migration Pattern**: `try gltf_asset.addTexture("MeshName", "uniform_name", "path.tga", config)` bridges ASSIMP texture-type with glTF uniform-name system
- **Animation Blending**: `playWeightAnimations()` handles sophisticated weight-based animation mixing essential for game_angrybot character animation
- **Custom Textures**: Override material textures with texture units starting at 10 to avoid conflicts