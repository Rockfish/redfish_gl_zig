# Plan 002: Interactive Demo Application

**Status**: 🔄 Active  
**Priority**: High  
**Started**: 2024-06-26  
**Target**: 2024-07-08  

## Overview

Create an interactive demo application that showcases the engine's GLB and glTF loading capabilities. The demo will feature model cycling, intelligent camera positioning, and a user-friendly interface that demonstrates both formats working seamlessly together.

## Prerequisites

- [x] Plan 001: GLB Format Support (completed)
- [x] Core asset loader with GLB support working
- [x] Integration tests passing for GLB loading

## Current Code Analysis

The existing `examples/new_gltf/` structure provides a solid foundation:
- **main.zig**: Basic window setup with hardcoded model loading
- **state.zig**: Comprehensive input handling and camera system with multiple motion types
- **run_app.zig**: Main application loop with model loading and rendering
- **render.zig**: Shader uniform setup (currently for external zgltf, needs adaptation)
- **assets_list.zig**: Comprehensive model path lists (108 glTF + 79 GLB models)
- **shaders/**: Basic, PBR, and player shaders available

## Implementation Plan

### Step 1: Model Management System
**Goal**: Create curated demo model list with cycling functionality

**Tasks**:
- [ ] Update `assets_list.zig` with combined demo model list
- [ ] Create model metadata structure `{path, name, format, category, description}`
- [ ] Prioritize model order: simple → complex → animated
- [ ] Add `current_model_index: usize` to State struct
- [ ] Implement 'n' (next) and 'b' (back) key handlers in `state.zig`
- [ ] Add model loading state tracking
- [ ] Handle wrap-around at list boundaries

**Curated Model Selection**:
- **Simple**: Box.glb, BoxTextured.glb, Triangle.gltf (3 models)
- **Animated**: Fox.glb, CesiumMan.glb, BoxAnimated.glb (3 models)  
- **Complex**: DamagedHelmet.glb, FlightHelmet.gltf, BrainStem.glb (3 models)
- **Format comparison**: Duck.gltf vs Duck.glb, Avocado.gltf vs Avocado.glb (4 models)
- **Edge cases**: Unicode❤♻Test.glb, BoxInterleaved.glb (2 models)
- **Total**: ~15 carefully selected models

### Step 2: Asset Loader Integration
**Goal**: Replace hardcoded builder with our new GLB-compatible asset loader

**Tasks**:
- [ ] Update `run_app.zig` to remove external Builder dependency
- [ ] Replace with `core.asset_loader.GltfAsset`
- [ ] Update model loading to use our GLB implementation
- [ ] Create model builder bridge to adapt GltfAsset to existing Model/rendering system
- [ ] Ensure GLB and glTF files load identically
- [ ] Add loading progress/error display
- [ ] Maintain texture loading compatibility

### Step 3: Camera Auto-Positioning
**Goal**: Implement intelligent camera positioning based on model bounds

**Tasks**:
- [ ] Add bounding box calculation from glTF data
- [ ] Calculate appropriate camera distance and position
- [ ] Implement frame-to-fit functionality with 'f' key
- [ ] Add auto-positioning algorithm for new models
- [ ] Preserve manual camera controls (WASD, mouse, scroll)
- [ ] Enhance existing camera system with better defaults

### Step 4: User Interface Enhancements
**Goal**: Add informative display and model information

**Tasks**:
- [ ] Create `ui_display.zig` for status system
- [ ] Current model info: "3/15: Box (GLB) - Simple geometry test"
- [ ] Loading status with progress indication
- [ ] Camera position and target display
- [ ] Model statistics (meshes, vertices, textures, animations)
- [ ] Help system with key binding display
- [ ] Model category information
- [ ] Performance metrics (FPS, load time)

### Step 5: Error Handling & Polish
**Goal**: Robust error handling and user experience

**Tasks**:
- [ ] Graceful handling of missing model files
- [ ] Corrupted GLB file error display
- [ ] Unsupported glTF feature warnings
- [ ] Display errors without crashing demo
- [ ] Model loading caching for performance
- [ ] Texture memory management
- [ ] Frame rate monitoring and display

### Step 6: Rendering System Updates
**Goal**: Leverage existing shader system with glTF material support

**Tasks**:
- [ ] Update `render.zig` for our asset loader system
- [ ] Adapt shader uniform setup for our asset loader
- [ ] Support PBR material properties from glTF
- [ ] Maintain compatibility with basic and PBR shaders
- [ ] Animation system integration from angry_gl_zig concepts
- [ ] Support glTF animation playback
- [ ] Add animation controls ('=' next, '-' prev, '0' reset)

### Step 7: Build System Integration
**Goal**: Ensure demo builds and runs properly

**Tasks**:
- [ ] Update `build.zig` with demo app build target
- [ ] Add `zig build demo` and `zig build demo-run` commands
- [ ] Ensure examples/new_gltf/ compiles with our changes
- [ ] Link with our updated core module
- [ ] Include asset path validation
- [ ] Graceful fallback for missing models

### Step 8: Demo Polish & Testing
**Goal**: Final testing and user experience improvements

**Tasks**:
- [ ] Test all 15 curated models load correctly
- [ ] Verify GLB and glTF format parity
- [ ] Performance testing with large models
- [ ] User interface responsiveness testing
- [ ] Animation playback validation
- [ ] Error condition testing
- [ ] Documentation and usage instructions

## Key Files to Modify

### Primary Changes:
- `examples/new_gltf/main.zig` - Remove hardcoded paths, add demo logic
- `examples/new_gltf/run_app.zig` - Replace Builder with GltfAsset, add model cycling
- `examples/new_gltf/state.zig` - Add model navigation keys, enhance UI state
- `examples/new_gltf/assets_list.zig` - Create curated demo model list
- `examples/new_gltf/render.zig` - Adapt to our asset loader system

### New Files:
- `examples/new_gltf/demo_models.zig` - Curated model metadata and management
- `examples/new_gltf/ui_display.zig` - Status and help display system

## User Controls

### Model Navigation:
- **'n'** - Next model
- **'b'** - Back/previous model
- **'r'** - Reset camera position
- **'f'** - Frame-to-fit current model

### Camera Controls (existing):
- **WASD** - Camera movement (multiple motion types)
- **Arrow keys** - Alternative movement
- **Mouse scroll** - Zoom in/out
- **1-2** - Camera mode (LookTo/LookAt)
- **6-9** - Motion type (Translate/Orbit/Circle/Rotate)

### Animation Controls:
- **'0'** - Reset animation
- **'+'** / **'='** - Next animation
- **'-'** - Previous animation

### Display Controls:
- **'t'** - Toggle performance display
- **'h'** - Toggle help display

## Success Criteria

- [ ] Demo cycles through 15 curated models smoothly with 'n'/'b' keys
- [ ] Both GLB and glTF files load and render identically
- [ ] Camera auto-positions appropriately for each model size
- [ ] UI displays current model info: "5/15: Duck (GLB) - Waterfowl model"
- [ ] Loading status shows progress for large models
- [ ] Animation controls work for animated models (Fox, CesiumMan)
- [ ] Error handling gracefully manages missing/corrupted files
- [ ] Performance is acceptable for all curated models
- [ ] Format comparison models demonstrate GLB/glTF parity
- [ ] Help system guides users through available controls

## Testing Strategy

### Model Categories:
1. **Simple Models** - Verify basic loading and rendering
2. **Animated Models** - Test animation playback and controls
3. **Complex Models** - Performance and memory usage validation
4. **Format Pairs** - GLB vs glTF comparison validation
5. **Edge Cases** - Unicode, interleaved data, error handling

### Performance Targets:
- Model loading: < 2 seconds for complex models
- Frame rate: > 30 FPS during normal operation
- Memory usage: Reasonable texture memory management
- Error recovery: No crashes on missing/corrupted files

## Notes & Decisions

**2024-06-26**: Demo application plan created as Phase 2 of original GLB support plan. Separated into dedicated plan for better organization and focus. Leverages existing examples/new_gltf/ structure while integrating our new GLB asset loader.

**Design Philosophy**: 
- Progressive complexity showcase (simple → advanced)
- Format agnostic demonstration (GLB and glTF seamless)
- User-friendly controls with clear feedback
- Robust error handling for production-quality demo

## Related Files

- `examples/new_gltf/` - Demo application source directory
- `src/core/asset_loader.zig` - GLB/glTF loading backend
- `plan/001-glb-support.md` - Prerequisite GLB implementation
- `tests/integration/glb_loading_test.zig` - GLB validation tests

## Next Steps

Upon completion, this demo will serve as:
1. **Validation tool** for GLB/glTF format support
2. **Showcase application** for engine capabilities  
3. **Testing platform** for future enhancements
4. **Reference implementation** for other developers

Next planned development: **Plan 003: Shader Improvements** - Enhanced PBR shaders and material systems.