# redfish_gl_zig - 3D Graphics Engine

## Project Overview

**redfish_gl_zig** is a 3D graphics engine written in Zig focused on real-time rendering of animated glTF models with physically-based rendering (PBR). The engine supports character animation, texturing, lighting, and camera controls.

### Current Status (2024-06-25)
- ✅ Core rendering pipeline with OpenGL 4.0
- ✅ Architecture refactoring completed (commit 6725b17)
- ✅ Format-agnostic rendering components (Model, Mesh, Animator)
- ✅ Skeletal animation system with clips
- ✅ PBR material support (diffuse, specular, emissive, normals)
- ✅ Camera controls (WASD movement + mouse look)
- ✅ Custom math library integration
- 🔄 **Active Plan**: Plan 001 - GLB Support and Demo App
- 🔄 Working on: GLB binary format parsing and interactive demo
- 📋 Next: Implement GLB magic header detection

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
├── cglm/          # C math library
└── miniaudio/     # Audio support
```

### Key Components

#### Graphics Pipeline
- **Renderer**: OpenGL 4.0 core profile
- **Shaders**: Vertex/fragment shaders for PBR materials
- **Textures**: Support for diffuse, specular, emissive, and normal maps
- **Camera**: Free-look camera with movement controls

#### Animation System
- **Clips**: Frame-based animation clips with repeat modes
- **Animator**: Manages playback and transitions
- **Bones**: Skeletal animation support for character models

#### Math Library (`src/math/`)
- Custom Zig implementations with CGLM integration
- Types: `Vec2`, `Vec3`, `Vec4`, `Mat4`, `Quat`
- Functions: Transformations, projections, ray casting

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
- glTF models should be loaded through `ModelBuilder` in `src/core/gltf/`
- Textures are cached and managed centrally
- Use descriptive material names for texture associations

### Animation
- Animation clips are defined with start/end frames and repeat modes
- Use `AnimationClip.init()` for creating clips
- Transitions between clips should specify blend duration

### Error Handling
- Use Zig's error unions for fallible operations
- Prefer explicit error handling over assertions
- Log errors with context using `std.debug.print()`

## Build & Development

### Building
```bash
# Build main example
zig build zgltf_port

# Run main example  
zig build zgltf_port-run

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
- **cglm**: C math library for performance-critical operations
- **miniaudio**: Audio playback support

## Known Issues & TODOs

### Current Issues
- Memory management needs review in texture cache cleanup
- Animation blending not yet implemented
- Single model rendering only (no scene graph)

### Next Steps
1. **Complete `examples/demo_app/main.zig` implementation**
   - Integrate custom glTF parser with rendering pipeline
   - Port existing functionality from zgltf_port example
   - Ensure shader integration works with new architecture

2. **Test the new custom glTF parser**
   - Verify model loading works correctly
   - Test animation playback with custom implementation
   - Compare performance with third-party zgltf approach

3. **Ensure feature parity with zgltf_port example**
   - Camera controls and movement
   - Texture loading and material support
   - Animation clip playback
   - Lighting and PBR rendering

4. **Future enhancements** (after refactoring complete):
   - Implement animation state machine for character controllers
   - Add support for multiple models in a scene
   - Implement shadow mapping for better lighting
   - Add audio integration for ambient sounds
   - Create scene serialization system

## Current Active Plans

See `plan/active-plans.md` for detailed project roadmap.

**Current Focus**: Plan 001 - GLB Support and Demo App (Phase 1: GLB Implementation)

## Recent Changes

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
- Previous demo executable is was `examples/zgltf_port/main.zig`
- Main executable being developed is currently `examples/demo_app/main.zig`
- Shaders located in `examples/demo_app/shaders/`
- Custom math library prioritized over external dependencies. 
- Suggest adding math functions to custom math library as needed.
