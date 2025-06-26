# Plan 005: Basic Scene Management

**Status**: 📋 Planned  
**Priority**: Low  
**Started**: TBD  
**Target**: 1-2 weeks  

## Overview

Implement essential scene management features to support multiple models, basic transform hierarchy, and simple scene composition. This focused plan enables loading and positioning multiple objects in 3D space with basic optimization.

## Prerequisites

- [x] Plan 001 (GLB Support) completed
- [ ] Plan 002 (Demo Application) completed
- [ ] Plan 003 (Basic PBR Shaders) completed
- [ ] Plan 004 (Basic Animation System) completed or in progress
- [ ] Multiple models loading reliably

## Phase 1: Multi-Model Support

### Basic Scene Structure
- [ ] Create simple scene container for multiple models
- [ ] Implement model positioning and transforms
- [ ] Add basic parent-child relationships
- [ ] Support loading multiple models simultaneously
- [ ] Create scene update and render loop

### Transform Management
- [ ] Implement local vs world transform calculations
- [ ] Add transform hierarchy support
- [ ] Create transform matrix management
- [ ] Support model positioning, rotation, and scaling
- [ ] Add transform animation support for scene objects

## Phase 2: Basic Optimization

### Simple Culling
- [ ] Implement basic frustum culling
- [ ] Add distance-based model culling
- [ ] Create simple bounding box calculations
- [ ] Support culling for off-screen objects
- [ ] Add basic performance monitoring

### Scene Composition
- [ ] Create simple scene building API
- [ ] Add support for environment models (like Sponza)
- [ ] Support multiple character models in scene
- [ ] Implement basic scene validation
- [ ] Add scene statistics and debugging info

## Success Criteria

- [ ] Multiple models can be loaded and positioned in 3D space
- [ ] Basic transform hierarchy works correctly
- [ ] Simple frustum culling improves performance
- [ ] Scene composition API is easy to use
- [ ] Demo app can show multiple models together
- [ ] System supports both static and animated models in same scene

## Testing Scenarios

### Multi-Model Scenes
- Load multiple models from assets_list.zig into single scene
- Test basic transform hierarchies
- Verify culling with models outside camera view

### Mixed Content Scenes
- Static environment model (like architectural scenes)
- Multiple character models with animations
- Combination of simple and complex models

### Performance Validation
- Tens of simple objects (Box.glb instances)
- Basic culling effectiveness
- Memory usage with multiple models

## Scope Limitations

**Not Included in This Plan** (moved to backlog):
- Advanced spatial optimization (octrees, etc.)
- Complex scene serialization formats
- Dynamic batching and instancing
- Scene streaming and memory management
- Advanced culling systems
- Scene editing tools
- Multi-scene support

## Notes & Decisions

**Focus**: This plan focuses on essential multi-model support that enables basic scene composition. Advanced optimization and tooling features are deferred to later iterations.

## Related Files

- `src/core/scene.zig` - Basic scene management (to be created)
- `src/core/transform.zig` - Enhanced transform system
- `examples/new_gltf/scene_demo.zig` - Scene composition demo