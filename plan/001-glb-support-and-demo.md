# Plan 001: GLB Support and Demo App

**Status**: 🔄 Active  
**Priority**: High  
**Started**: 2024-06-25  
**Target**: 2024-07-05  

## Overview

Add support for loading GLB (binary glTF) files alongside existing *.gltf support, and create an interactive demo application that showcases the engine's capabilities with both formats. This plan implements GLB parsing while maintaining clean separation between format handling and rendering.

## Prerequisites

- [x] Core architecture refactoring completed (commit 6725b17)
- [x] Custom math library integration working
- [x] Asset loader separated from glTF-specific parsing

## Phase 1: GLB Format Support

### GLB Parser Implementation
- [x] Add GLB magic header detection (0x46546C67 "glTF")
- [x] Implement GLB header parsing (magic, version, length)
- [x] Add GLB chunk parsing (JSON and BIN chunks)
- [x] Validate chunk types (0x4E4F534A "JSON", 0x004E4942 "BIN\0")
- [x] Handle 4-byte alignment padding

### Asset Loader Integration
- [x] Add file type detection (*.gltf vs *.glb)
- [x] Modify `load()` function to route by format
- [x] Update `loadBufferData()` for GLB binary chunks
- [x] Pre-populate buffer_data with GLB embedded data
- [x] Add GLB-specific error handling

### Data Structures
- [x] Create GLB data structure for parsed chunks
- [x] Ensure proper memory alignment for binary data
- [x] Add GLB format validation functions

## Phase 2: Demo Application

### Model Management
- [ ] Create curated demo model list from assets_list.zig
- [ ] Implement model cycling with 'b' (back) and 'n' (next) keys
- [ ] Add model loading with progress indication
- [ ] Handle missing files gracefully

### Camera System
- [ ] Implement auto-positioning based on model bounding box
- [ ] Add manual camera controls (WASD + mouse)
- [ ] Add 'r' key for camera reset
- [ ] Add 'f' key for frame-to-fit functionality

### User Interface
- [ ] Display current model name and format (GLB/GLTF)
- [ ] Show model index (e.g., "3/10: Damaged Helmet (GLB)")
- [ ] Add loading status display
- [ ] Show camera position and model statistics

### Demo Model Selection
- [ ] Simple models: Box.glb, BoxTextured.glb
- [ ] Animated models: Fox.glb, CesiumMan.glb, BoxAnimated.glb
- [ ] Complex models: DamagedHelmet.glb, FlightHelmet.gltf, BrainStem.glb
- [ ] Format comparison: Duck.gltf vs Duck.glb, Avocado.gltf vs Avocado.glb

## Phase 3: Validation Tests

### Test Infrastructure
- [x] Create tests/ directory structure
- [x] Set up test runner framework
- [x] Add test model definitions

### Unit Tests
- [x] GLB header parsing tests
- [x] Chunk extraction validation
- [x] Binary data alignment tests
- [x] Error condition handling tests

### Integration Tests
- [x] GLB loading integration test (Box.glb)
- [ ] Format parity tests (compare .gltf vs .glb loading)
- [ ] Mesh data comparison validation
- [ ] Texture loading verification
- [ ] Animation data consistency checks

### Edge Case Tests
- [ ] Unicode filename handling (Unicode❤♻Test.glb)
- [ ] Corrupted GLB file handling
- [ ] Multiple binary chunk support
- [ ] Interleaved vertex data (BoxInterleaved.glb)

## Success Criteria

- [x] GLB files load correctly (✅ Box.glb loads successfully with 1 mesh, 1 buffer, 648 bytes)
- [ ] GLB files render identically to GLTF equivalents
- [ ] Demo app cycles through models smoothly with keyboard controls
- [ ] Camera auto-positions appropriately for different model sizes
- [x] Basic GLB validation tests pass (✅ Integration test successful)
- [ ] Error handling is robust for malformed files
- [ ] Performance is acceptable for large models

## Testing Models

### Simple Test Cases
- `Box/glTF-Binary/Box.glb` - Minimal geometry
- `BoxTextured/glTF-Binary/BoxTextured.glb` - Basic texturing
- `Triangle/glTF/Triangle.gltf` - Comparison reference

### Animation Test Cases
- `BoxAnimated/glTF-Binary/BoxAnimated.glb` - Simple animation
- `Fox/glTF-Binary/Fox.glb` - Character animation
- `CesiumMan/glTF-Binary/CesiumMan.glb` - Rigged character

### Complex Models
- `DamagedHelmet/glTF-Binary/DamagedHelmet.glb` - PBR showcase
- `FlightHelmet/glTF/FlightHelmet.gltf` - High-quality reference
- `BrainStem/glTF-Binary/BrainStem.glb` - Detailed geometry

### Edge Cases
- `Unicode❤♻Test/glTF-Binary/Unicode❤♻Test.glb` - Unicode handling
- `BoxInterleaved/glTF-Binary/BoxInterleaved.glb` - Vertex data layout
- `MorphStressTest/glTF-Binary/MorphStressTest.glb` - Complex features

## Notes & Decisions

**2024-06-25**: Plan created based on architecture analysis. Decided to implement GLB parsing in asset_loader.zig rather than gltf/parser.zig to maintain clean separation of concerns. Parser stays focused on JSON, asset loader handles format orchestration.

**2024-06-26**: Phase 1 completed! GLB parsing implementation successful:
- ✅ GLB header and chunk parsing working correctly
- ✅ Binary data alignment issues resolved 
- ✅ Asset loader integration complete with format routing
- ✅ Parser compilation issues fixed (Mat4, Vec3, Quat array initialization)
- ✅ Integration test passing: Box.glb loads with 1 mesh, 1 buffer (648 bytes embedded)
- 🎯 Ready to proceed to Phase 2: Demo Application

## Related Files

- `src/core/asset_loader.zig` - Main GLB implementation location
- `src/core/gltf/parser.zig` - JSON parsing (no changes needed)
- `examples/new_gltf/main.zig` - Demo application
- `examples/new_gltf/assets_list.zig` - Test model paths
- `tests/gltf/` - Validation test suite (to be created)