//! Rendering pipeline constants that must stay synchronized between
//! CPU (Zig) and GPU (GLSL shaders).
//!
//! IMPORTANT: If you change these values, you MUST also update:
//! - All shader files that reference these constants
//! - This is enforced manually - there is no automatic synchronization
//!
//! Example shader references:
//! - examples/demo_app/shaders/pbr.vert
//! - games/level_01/shaders/animated_pbr.vert
//! - games/angrybot/shaders/player_shader.vert

/// Maximum number of joints supported for skeletal animation
/// Must match `const int MAX_JOINTS` in all animated shaders
pub const MAX_JOINTS: usize = 100;

/// Maximum number of bones that can influence a single vertex
/// Corresponds to ivec4/vec4 size in shaders (4 components)
/// Used implicitly by vertex attribute types
pub const MAX_JOINT_INFLUENCE: u32 = 4;

/// OpenGL vertex attribute locations
/// Must match `layout(location = X)` in all vertex shaders
pub const VertexAttr = struct {
    pub const POSITION: u32 = 0;
    pub const TEXCOORD: u32 = 1;
    pub const NORMAL: u32 = 2;
    pub const TANGENT: u32 = 3;
    pub const COLOR: u32 = 4;
    pub const JOINTS: u32 = 5;
    pub const WEIGHTS: u32 = 6;
    pub const INSTANCE_MATRIX: u32 = 7;
};
