# Changelog

## Recent Changes

### 2025-07-08 - ASSIMP-Style Asset Loading Options 🔧
- **Asset Loading Architecture Refactoring**: Implemented ASSIMP-style configuration options for glTF asset loading
- **Normal Generation System**: Created comprehensive normal generation system with three modes:
  - **Skip Mode**: Uses shader fallback lighting for models without normals
  - **Simple Mode**: Generates uniform upward-facing normals (0, 1, 0) for all vertices
  - **Accurate Mode**: Calculates proper normals from triangle geometry using cross products
- **Configuration API**: Added `setNormalGenerationMode()` method following ASSIMP patterns
  - Usage: `gltf_asset.setNormalGenerationMode(.accurate)` before calling `buildModel()`
  - Centralized preprocessing at asset level, not during mesh creation
  - Automatic detection - only generates normals for mesh primitives that lack them
- **Technical Implementation**:
  - Moved `NormalGenerationMode` enum from `mesh.zig` to `asset_loader.zig`
  - Added `generated_normals` HashMap to `GltfAsset` with composite keys `(mesh_index << 32 | primitive_index)`
  - Implemented `generateMissingNormals()` called during `buildModel()` preprocessing
  - Updated mesh initialization to use pre-generated normals via `getGeneratedNormals()`
  - Moved normal generation functions to asset loader for centralized processing
- **Fox Model Lighting Fix**: Resolved Fox model's black appearance from certain angles
  - Fox model lacks normal vectors in glTF data, causing lighting failures
  - Accurate normal generation now automatically creates proper normals from triangle geometry
  - Test output: "Generated accurate normals for mesh 0 primitive 0 (1728 vertices)"
- **Extensible Pattern**: Established foundation for additional asset loading options (future texture settings, optimization flags, etc.)
- **Files Modified**:
  - `src/core/asset_loader.zig` - Added normal generation system and ASSIMP-style configuration
  - `src/core/mesh.zig` - Removed duplicate normal generation, updated to use pre-generated normals
  - `examples/demo_app/run_app.zig` - Configured accurate normal generation for all models
- **Memory Management**: Pre-generated normals stored efficiently in HashMap, cleaned up with asset lifecycle
- **Development Impact**: Provides robust foundation for handling models with missing or incomplete geometry data

### 2025-07-06 - Screenshot & Debug System Implementation 📸
- **Framebuffer Screenshot System**: Implemented complete screenshot capture functionality
  - `examples/demo_app/screenshot.zig` - OpenGL framebuffer creation and management
  - `examples/demo_app/screenshot_manager.zig` - High-level screenshot coordination
  - Automatic PNG saving via zstbi library integration
  - Image vertical flipping for correct OpenGL-to-file orientation
  - Framebuffer auto-resizing to match viewport dimensions
- **Enhanced Shader Debug System**: Significantly expanded shader uniform debugging capabilities
  - `src/core/shader.zig` - Added `dumpDebugUniformsJSON()` for structured JSON output
  - `src/core/shader.zig` - Added `saveDebugUniforms()` for direct file export
  - Automatic timestamp inclusion in debug output
  - Comprehensive uniform type support (Mat4, Vec3, floats, etc.)
- **F12 Screenshot Trigger**: Integrated screenshot system into demo application
  - `examples/demo_app/state.zig` - Added F12 key handling
  - `examples/demo_app/run_app.zig` - Complete integration with render loop
  - Synchronized capture of both visuals and shader state
  - Temporary debug enable/disable for consistent uniform capture
- **Coordinated Output System**: Synchronized file generation with shared timestamps
  - Output directory: `/tmp/redfish_screenshots/`
  - Filename format: `YYYY-MM-DD_HH.MM.SS.mmm_pbr_{screenshot|uniforms}.{png|json}`
  - Automatic directory creation and error handling
- **Development Workflow Enhancement**: Added powerful debugging tools for shader development
  - Visual debugging via F12 screenshots during runtime
  - Complete shader state inspection with JSON export
  - Essential tooling for Plan 003 PBR shader development

### 2025-07-06 - Professional Development Workflow Tools 🚀
- **Just Recipe System**: Created comprehensive `justfile` with 25+ development commands
  - `just dev` - Auto-rebuild and run with file watching
  - `just pbr-dev` - Specialized shader development workflow for Plan 003
  - `just test` - Run all test suites
  - `just stats` - Project statistics with tokei integration
  - `just bench-build` - Build performance benchmarking with hyperfine
  - `just validate-shaders` - GLSL shader validation pipeline
  - `just doctor` - Development environment verification
- **Watchexec Integration**: Created specialized file watchers for different development modes
  - `scripts/watch-dev.sh` - General development with auto-rebuild/run
  - `scripts/watch-shaders.sh` - Shader development with GLSL validation
  - `scripts/watch-build.sh` - Build-only watcher for fast compilation feedback
- **Development Documentation**: Created comprehensive `DEVELOPMENT.md` workflow guide
  - Quick start commands and common workflows
  - Plan 003 shader development patterns
  - Performance analysis and debugging tools
  - Complete demo app controls reference
- **Tool Recommendations**: Identified and documented essential development tools
  - `glslang` for shader validation (critical for Plan 003)
  - `hyperfine` for performance benchmarking
  - `tokei` for code statistics
  - `watchexec` for file watching
  - `just` for command recipes
- **Build System Integration**: Enhanced development infrastructure
  - Updated `.gitignore` for tool artifacts
  - Integrated workflow documentation into project structure
  - Added environment validation and setup verification
- **Files Added**:
  - `justfile` - Comprehensive command recipe system
  - `DEVELOPMENT.md` - Complete workflow documentation
  - `scripts/watch-dev.sh` - General development watcher
  - `scripts/watch-shaders.sh` - Shader development watcher
  - `scripts/watch-build.sh` - Build-only watcher
- **Development Experience**: Transformed from manual commands to professional automated workflow
  - Fast iteration cycles for shader development (Plan 003 ready)
  - Immediate feedback on compilation errors
  - Automated testing and quality assurance
  - Performance monitoring and analysis tools

### 2025-07-05 - Code Organization and glTF Development Tools ✨
- **Transform Refactoring**: Moved `toTranslationRotationScale` function from Mat4 to Transform module
  - Eliminated unnecessary `TrnRotScl` temporary struct
  - Added `Transform.extractTransformFromMatrix()` as private function
  - Updated `Transform.fromMatrix()` to use new internal implementation
  - Cleaned up Mat4 by removing domain-specific logic
- **Matrix Documentation Enhancement**: Added comprehensive column-major documentation to Mat4 struct
  - Documented data storage as `data[column][row]` with clear indexing
  - Explained column meanings for transform matrices
  - Added OpenGL/CGLM compatibility notes
- **Git Commit Template Improvement**: Enhanced `.claude/commands/git-commit.md` with clear structure guidelines
  - Added format specifications (72 character limit, imperative mood)
  - Included concrete examples and best practices
  - Structured format with concise description followed by bullet points
- **glTF Development Tools**: Created comprehensive glTF inspection and reporting system
  - **New Module**: `src/core/gltf/report.zig` - Modern glTF inspection tool
  - **Three Output Methods**: Console printing, string generation, file writing
  - **Comprehensive Analysis**: Scenes, meshes, accessors, animations, materials, textures
  - **Core Integration**: Available as `@import("core").gltf_report`
  - **Test Program**: `examples/demo_app/test_report.zig` demonstrates usage
  - **Documentation**: `src/core/gltf/README.md` with usage examples
- **Legacy Code Cleanup**: Removed `examples/zgltf_port` directory after preserving functionality
  - Modernized legacy `gltf_report.zig` to use native glTF implementation
  - Replaced zgltf dependency with core glTF system
  - Maintained all inspection capabilities while improving architecture
- **Files Modified**:
  - `src/core/transform.zig` - Added matrix decomposition function
  - `src/math/mat4.zig` - Removed temp struct, added documentation
  - `src/core/gltf/report.zig` - NEW comprehensive glTF analysis tool
  - `src/core/main.zig` - Added gltf_report export
  - `examples/demo_app/test_report.zig` - NEW test program
  - `.claude/commands/git-commit.md` - Enhanced template
  - **REMOVED**: `examples/zgltf_port/` directory (functionality preserved)
- **Code Quality**: All changes formatted with `zig fmt` and verified for compilation

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