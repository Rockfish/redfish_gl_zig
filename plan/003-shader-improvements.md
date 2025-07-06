# Plan 003: Basic PBR Shaders

**Status**: 🔄 Active - Phase 2  
**Priority**: High  
**Started**: 2025-07-04  
**Phase 1 Completed**: 2025-07-06  
**Target**: 1-2 weeks total  

## Overview

Implement basic PBR (Physically Based Rendering) shaders to make models look realistic with proper materials. This focused plan adds essential visual quality without complex lighting systems, building on the GLB support and demo application foundation.

## Prerequisites

- [x] Plan 001 (GLB Support) completed
- [x] Plan 002 (Demo Application) completed
- [x] Stable model loading for both GLTF and GLB formats
- [x] Demo application working with basic shaders

## Phase 1: Shader Debugging Infrastructure ✅ COMPLETED

### Uniform Value Debugging System ✅
- [x] **Shader Debug State**: Added `debug_enabled`, `debug_arena`, `debug_uniforms` to Shader struct
- [x] **Enable/Disable Functions**: `enableDebug()` and `disableDebug()` with proper memory management
- [x] **Clear Function**: `clearDebugUniforms()` resets captured values each frame
- [x] **Custom Debug Values**: `addDebugValue()` for manual insertion of debug info (camera pos, light pos, etc.)
- [x] **Formatted Output**: `dumpDebugUniforms()` provides console/buffer output with shader info and uniform counts
- [x] **Render Loop Integration**: 'G' key toggle for debug mode, 'U' key for debug dump output
- [x] **Automatic Capture**: `captureDebugUniform()` automatically captures all uniform values during `getUniformLocation()`
- [x] **Type Support**: Comprehensive type handling for bool, int, float, Vec2/3/4, Mat3/4, arrays
- [x] **Testing**: Validated with current shaders in demo application

### Implementation Details
- **Memory Management**: Uses ArenaAllocator for efficient debug data allocation/cleanup
- **Performance**: Debug capture only active when enabled, minimal overhead when disabled
- **User Interface**: Integrated with demo app controls ('G' toggle, 'U' dump)
- **Output Format**: Professional debug output with shader file names and uniform counts
- **Custom Values**: Real-time camera position, target, light position, and frame timing

### Remaining Phase 1 Items
- [x] Add framebuffer rendering for scene snapshots
- [x] Create timestamped bitmap and text file output system

## Phase 2: Core PBR Implementation 🔄 CURRENT PHASE

### PBR BRDF Foundation
- [ ] **Next Task**: Implement basic PBR BRDF (Cook-Torrance model) in fragment shader
- [ ] Add metallic-roughness workflow support with proper material uniforms
- [ ] Create proper material property handling in Model/Mesh rendering
- [ ] Enhance shader compilation system with PBR shader variants

### Essential Texture Support
- [ ] Enhance albedo/base color texture handling
- [ ] Implement normal mapping with proper tangent space
- [ ] Add metallic and roughness texture support
- [ ] Support basic emissive materials

### Basic Lighting Model
- [ ] Implement single directional light (sun)
- [ ] Add simple ambient lighting
- [ ] Create proper gamma correction
- [ ] Ensure linear color space workflow

## Phase 3: Material Quality

### Material Features
- [ ] Support vertex colors
- [ ] Add proper alpha testing and blending
- [ ] Implement double-sided material rendering
- [ ] Add basic texture coordinate support

### Visual Polish
- [ ] Improve material preview in demo
- [ ] Add material property visualization
- [ ] Ensure consistent material appearance
- [ ] Optimize shader performance

## Success Criteria

### Phase 1: Shader Debugging ✅ COMPLETED
- [x] **Uniform Debugging System**: Real-time uniform value capture and inspection
- [x] **Debug Controls**: Toggle and dump functionality integrated into demo app
- [x] **Professional Output**: Formatted debug information with shader context
- [x] **Development Workflow**: Enhanced shader development with debugging tools

### Phase 2: Core PBR Implementation 🔄 IN PROGRESS
- [ ] Models render with realistic PBR materials instead of flat shading
- [ ] Metallic and roughness values produce expected visual results
- [ ] Normal maps add proper surface detail
- [ ] Materials look consistent across different models
- [ ] Demo app shows clear visual improvement over basic shaders
- [ ] Shader performance is acceptable for real-time rendering

### Phase 3: Material Quality
- [ ] Comprehensive material feature support
- [ ] Visual polish and optimization
- [ ] Production-ready PBR pipeline

## Testing Models for PBR Features

### Basic PBR Tests
- `MetalRoughSpheres/glTF-Binary/MetalRoughSpheres.glb` - Material variety showcase
- `DamagedHelmet/glTF-Binary/DamagedHelmet.glb` - Complex real-world PBR
- `FlightHelmet/glTF/FlightHelmet.gltf` - High-quality material reference

### Material Feature Tests
- `BoxTextured/glTF-Binary/BoxTextured.glb` - Basic texture mapping
- `NormalTangentTest/glTF-Binary/NormalTangentTest.glb` - Normal mapping
- `EmissiveStrengthTest/glTF-Binary/EmissiveStrengthTest.glb` - Emissive materials

### Quality Validation
- `SpecGlossVsMetalRough/glTF-Binary/SpecGlossVsMetalRough.glb` - Workflow comparison
- `Avocado/glTF-Binary/Avocado.glb` - Organic material testing

## Scope Limitations

**Not Included in This Plan** (moved to backlog):
- Multiple light sources
- Shadow mapping
- Environment mapping/IBL
- Post-processing effects
- Advanced material extensions
- Performance optimizations beyond basic level

## Notes & Decisions

**Focus**: This plan focuses on making models look good with proper materials rather than complex lighting. The goal is realistic material appearance with a single light source.

**Phase 1 Achievement**: Successfully implemented comprehensive shader debugging infrastructure with automatic uniform capture, real-time debugging controls, and professional output formatting. This provides excellent foundation for PBR shader development and validation.

**Current Phase**: Phase 2 - Core PBR Implementation with Cook-Torrance BRDF model.

**Development Tools Ready**: Enhanced workflow with `just pbr-dev` for shader development with validation, and robust debugging system for rapid PBR iteration.

## Phase Progress Summary

### ✅ Phase 1 Completed (2025-07-06)
**Shader Debugging Infrastructure** - Complete uniform value debugging system integrated into the render pipeline. Key achievements:
- Real-time uniform capture and inspection during rendering
- Professional debug output with shader context and uniform counts  
- Integrated demo app controls ('G' toggle debug, 'U' dump output)
- Memory-efficient ArenaAllocator-based debug data management
- Comprehensive type support for all shader uniform types
- Enhanced development workflow with `just pbr-dev` command for shader iteration

### 🔄 Phase 2 Current Focus
**Core PBR Implementation** - Next milestone is implementing Cook-Torrance BRDF model:
- **Current Task**: Implement basic PBR BRDF in fragment shader
- **Priority**: Metallic-roughness workflow with proper material handling
- **Tools Ready**: Shader debugging system provides excellent validation capabilities
- **Workflow**: Use `just pbr-dev` for shader development with GLSL validation

### 📋 Phase 3 Planned
**Material Quality** - Polish and optimize the PBR pipeline for production use

## Related Files

- `examples/demo_app/shaders/pbr.vert` - PBR vertex shader (target for Phase 2)
- `examples/demo_app/shaders/pbr.frag` - PBR fragment shader (target for Phase 2)
- `src/core/shader.zig` - Shader management system ✅ (enhanced with debugging)
- `src/core/model.zig` - Material rendering integration (target for Phase 2)
- `justfile` - Development workflow commands (`just pbr-dev` for shader work)
- `DEVELOPMENT.md` - Complete workflow documentation