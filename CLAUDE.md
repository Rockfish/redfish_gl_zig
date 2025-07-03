# redfish_gl_zig - 3D Graphics Engine

## Project Overview

**redfish_gl_zig** is a 3D graphics engine written in Zig focused on real-time rendering of animated glTF models with physically-based rendering (PBR). The engine supports character animation, texturing, lighting, and camera controls.

### Current Status (2025-07-03)
- ✅ Core rendering pipeline with OpenGL 4.0
- ✅ Architecture refactoring completed (commit 6725b17)
- ✅ Format-agnostic rendering components (Model, Mesh, Animator)
- ✅ **Native glTF Animation System** - Complete ASSIMP replacement with glTF-native implementation
- ✅ **Skeletal Animation System** - Fully functional with Fox, Cesium Man, and mixed model support
- ✅ PBR material support (diffuse, specular, emissive, normals)
- ✅ Camera controls (WASD movement + mouse look)
- ✅ Custom math library integration with column-major matrix fixes
- ✅ **Completed**: Plan 001 - GLB Support (completed 2024-06-26)
- ✅ **Completed**: Plan 002 - Demo Application (fully completed 2025-07-02)
- ✅ **Major Milestone**: Complete Skeletal Animation Implementation
- 📋 Next: Mini-game integration and performance optimization

### Architecture

```
src/
├── core/           # Core engine systems
│   ├── gltf/      # glTF parsing and model loading
│   ├── shapes/    # Primitive geometry generators
│   └── utils/     # Utility functions
└── math/          # Custom math library (Vec2/3/4, Mat4, etc.)

examples/
└── zgltf_port/    # demo application using third party zgltf
└── demo_app/      # new demo application using core/gltf

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

#### Math Library (`src/math/`)
- Custom Zig implementations which used to have CGLM integration
- Types: `Vec2`, `Vec3`, `Vec4`, `Mat4`, `Quat`
- Functions: Transformations, projections, ray casting
- If there is missing needed functionality, propose adding it

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
- Do not add a signature at the end of commit messages

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

**Current Focus**: Plan 002 - Demo Application (completed core features, animation system implementation)

## Recent Changes

### 2025-07-03 - glTF Terminology Standardization ✨
- **ASSIMP to glTF Naming Transition**: Completed comprehensive naming changes throughout the codebase to use proper glTF terminology
- **Core System Updates**:
  - `MAX_BONES` → `MAX_JOINTS` (100 joint limit maintained)
  - `final_bone_matrices` → `joint_matrices` in Animator
  - `has_bones` → `has_skin` in MeshPrimitive
- **Shader Variable Updates**:
  - `inBoneIds` → `inJointIds` (vertex attribute for joint indices)
  - `finalBonesMatrices` → `jointMatrices` (uniform array for joint transforms)
  - `hasBones` → `hasSkin` (uniform flag for skinning detection)
  - `MAX_BONE_INFLUENCE` → `MAX_JOINT_INFLUENCE` (4 joints per vertex)
- **Semantic Improvements**:
  - Animation system now uses semantically correct glTF joint terminology
  - Eliminates legacy ASSIMP "bone" references for better code clarity
  - Maintains API compatibility while improving code readability
- **Files Updated**:
  - `src/core/animator.zig` - Core joint matrix system with proper terminology
  - `src/core/model.zig` - Joint matrix upload and shader integration
  - `src/core/mesh.zig` - Skin detection and vertex attribute setup
  - `examples/demo_app/shaders/player_shader.vert` - glTF-compliant shader variables
  - `examples/zgltf_port/shaders/player_shader.vert` - Consistency update
- **Production Ready**: All naming now aligns with glTF specification for professional development

### 2025-07-02 - Complete Skeletal Animation System ✨
- **Skeletal Animation Fully Functional**: Successfully completed and tested the glTF skeletal animation system
- **Model Compatibility**: Fox, Cesium Man, and Lantern models all working correctly
- **Technical Fixes Applied**:
  - Fixed bone ID vertex attributes from FLOAT to INT types (`gl.vertexAttribIPointer`)
  - Corrected MAX_BONES from 4 to 100 to support all joint matrices
  - Enhanced vertex shader logic for mixed skinned/non-skinned model support
  - Added proper bounds checking and safety for joint matrix calculations
  - Implemented real inverse bind matrix loading from glTF accessor data
- **Animation Features Working**:
  - Automatic first animation playback on model load
  - Animation switching with keyboard controls (=, -, 0 keys)
  - Real-time skeletal animation with proper bone transformations
  - Mixed model support (skinned + non-skinned in same application)
  - Proper node hierarchy handling for all model types
- **Files Updated**: 
  - `src/core/mesh.zig` - Fixed vertex attribute types and added debug output
  - `src/core/model.zig` - Fixed MAX_BONES constant and matrix upload
  - `src/core/animator.zig` - Enhanced joint matrix calculation with bounds checking
  - `examples/demo_app/shaders/player_shader.vert` - Smart bone detection and fallback logic
- **Ready for Production**: Animation system fully validated and ready for mini-game integration

### 2024-07-02 - Major Animation System Milestone ✨
- **Complete glTF Animation Implementation**: Successfully replaced ASSIMP-based animation system with native glTF implementation
- **API Compatibility Preserved**: All existing animation interfaces (`playClip()`, `playTick()`, `updateAnimation()`) work unchanged
- **Technical Architecture**:
  - ASSIMP ticks → glTF seconds timing system
  - `ModelBone`/`ModelNode` → glTF `Node`/`Skin` structures  
  - Bone offset matrices → glTF inverse bind matrices
  - Per-bone keyframes → per-channel animation evaluation
- **Core Components**: `AnimationClip`, `GltfAnimationState`, `Joint`, `NodeAnimation`, interpolation utilities
- **Performance**: Direct accessor reading, zero-allocation evaluation, maintained shader compatibility
- **Ready for Mini-Game Integration**: Seamless migration path for existing game code

### 2024-06-25
- **Project Planning System**: Created comprehensive plan tracking system
  - Added `plan/` directory with structured project plans
  - Plan 001: GLB Support and Demo App (active)
  - Plan 002-004: Future shader, animation, and scene management work
- **Session Continuity**: Enhanced CLAUDE.md to reference active plans

### 2024-06-24
- **Major Architecture Refactoring**: Completed transition from third-party zgltf to custom implementation
- **Core Module Reorganization**: Moved gltf-specific modules to general core modules
  - `src/core/gltf/animator.zig` → `src/core/animator.zig`
  - `src/core/gltf/mesh.zig` → `src/core/mesh.zig`
  - `src/core/gltf/model.zig` → `src/core/model.zig`
  - `src/core/gltf/node.zig` → `src/core/node.zig`
- **New Demo Structure**: Created `examples/demo_app/` for custom glTF implementation
- Updated math types integration with custom math library
- Added comprehensive Claude coding guidelines and project documentation

### Development Notes
- **Active demo**: `examples/demo_app/main.zig` (build target: `demo_app`)
- **Legacy demo**: `examples/zgltf_port/main.zig` (commented out in build.zig)
- **Shaders**: Located in `examples/demo_app/shaders/`
- **Math Library**: Pure Zig implementation in `src/math/` - add missing functions here
- **Asset Loading**: Use `GltfAsset` from `src/core/asset_loader.zig` for all model loading

## Coding Memories
- **Do not add signatures to commit messages**
- When adding a large list of items within {} put a comma after that last item so that the zig formatter will fold the line nicely
- When writing an if else statement always include {}
- When using a pattern like self.arena.allocator(), I prefer calling it once to set a local variable at the top of the function then using the local variable instead of making multiple function calls. It reduces the clutter and makes the code easier to read.
- **Animation System Architecture**: When replacing complex legacy systems (like ASSIMP), maintain API compatibility by keeping the same public interfaces while completely rewriting the internal implementation. This allows existing code to work unchanged while modernizing the underlying technology.
- **Type Import Patterns**: Always import types at the top of files rather than using inline `@import()` in function parameters. This improves readability and makes dependencies explicit.
- **Wrapper Struct Avoidance**: Avoid unnecessary wrapper structs that just hold references to other data. Direct references are cleaner and reduce cognitive overhead (e.g., `gltf_asset: *const GltfAsset` vs `gltf_asset_ref: GltfAssetRef`).