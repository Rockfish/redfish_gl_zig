# Changelog

## Recent Changes

### 2025-07-04 - Enhanced Model Statistics Display ✅
- **Model Statistics UI Enhancement**: Extended the demo application's model info display with comprehensive runtime statistics
- **New Statistics Added**:
  - Vertex count (total vertices across all mesh primitives)
  - Mesh primitive count (number of rendering primitives)
  - Texture count (loaded textures from asset)
  - Animation count (available animations in model)
- **Implementation Details**:
  - Added helper methods to `Model` struct: `getVertexCount()`, `getMeshPrimitiveCount()`, `getTextureCount()`, `getAnimationCount()`
  - Enhanced `renderModelInfo()` in UI system to display real-time statistics
  - Statistics update dynamically when switching between models
  - Professional formatting with color coding and proper alignment
- **Files Updated**:
  - `src/core/model.zig` - Added four new statistic methods to Model struct
  - `examples/demo_app/ui_display.zig` - Extended UI with statistics display section
  - `examples/demo_app/run_app.zig` - Modified to pass Model instance to UI render
  - `plan/002-demo-application.md` - Marked final open item as completed ✅
- **User Experience**: Provides complete technical insight into model complexity and structure
- **Completion**: Final remaining item from Plan 002 Demo Application now fully implemented

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