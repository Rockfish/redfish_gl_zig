# Plan 003: Basic PBR Shaders

**Status**: 📋 Planned  
**Priority**: Medium  
**Started**: TBD  
**Target**: 1-2 weeks  

## Overview

Implement basic PBR (Physically Based Rendering) shaders to make models look realistic with proper materials. This focused plan adds essential visual quality without complex lighting systems, building on the GLB support and demo application foundation.

## Prerequisites

- [x] Plan 001 (GLB Support) completed
- [ ] Plan 002 (Demo Application) completed
- [ ] Stable model loading for both GLTF and GLB formats
- [ ] Demo application working with basic shaders

## Phase 1: Core PBR Implementation

### PBR BRDF Foundation
- [ ] Implement basic PBR BRDF (Cook-Torrance model)
- [ ] Add metallic-roughness workflow support
- [ ] Create proper material property handling
- [ ] Add basic shader compilation system

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

## Phase 2: Material Quality

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

- [ ] Models render with realistic PBR materials instead of flat shading
- [ ] Metallic and roughness values produce expected visual results
- [ ] Normal maps add proper surface detail
- [ ] Materials look consistent across different models
- [ ] Demo app shows clear visual improvement over basic shaders
- [ ] Shader performance is acceptable for real-time rendering

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

## Related Files

- `examples/new_gltf/shaders/pbr.vert` - PBR vertex shader
- `examples/new_gltf/shaders/pbr.frag` - PBR fragment shader
- `src/core/shader.zig` - Shader management system
- `src/core/model.zig` - Material rendering integration