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

/// Standard uniform names used across shaders
/// Must match `uniform` declarations in all shader files
/// IMPORTANT: If you change these values, update the corresponding shaders
pub const Uniforms = struct {
    // Core transformation matrices
    pub const Mat_Projection: [:0]const u8 = "matProjection";
    pub const Mat_View: [:0]const u8 = "matView";
    pub const Mat_Model: [:0]const u8 = "matModel";
    pub const Projection_View: [:0]const u8 = "projectionView";

    // Animation system (glTF native)
    pub const Joint_Matrices: [:0]const u8 = "jointMatrices";
    pub const Node_Transform: [:0]const u8 = "nodeTransform";
    pub const Has_Skin: [:0]const u8 = "hasSkin";

    // Lighting and shadow mapping
    pub const Mat_Light_Space: [:0]const u8 = "matLightSpace";
    pub const Light_Space_Matrix: [:0]const u8 = "lightSpaceMatrix";

    // Legacy animation (ASSIMP - being phased out)
    pub const Final_Bones_Matrices: [:0]const u8 = "finalBonesMatrices";

    // Specialized uniforms (used in specific shaders)
    pub const Aim_Rot: [:0]const u8 = "aimRot";
    pub const Depth_Mode: [:0]const u8 = "depth_mode";
    pub const Time: [:0]const u8 = "time";
    pub const Nose_Pos: [:0]const u8 = "nosePos";

    // Picker shaders
    pub const Model: [:0]const u8 = "model";
    pub const View: [:0]const u8 = "view";
    pub const Projection: [:0]const u8 = "projection";
    pub const Model_Transform: [:0]const u8 = "model_transform";
    pub const Projection_View_Alt: [:0]const u8 = "projection_view";

    // Lighting uniforms
    pub const Ambient_Color: [:0]const u8 = "ambientColor";
    pub const Light_Color: [:0]const u8 = "lightColor";
    pub const Light_Direction: [:0]const u8 = "lightDirection";

    // Texture uniforms
    pub const Texture_Diffuse: [:0]const u8 = "textureDiffuse";
    pub const Texture_Normal: [:0]const u8 = "textureNormal";
    pub const Texture_Spec: [:0]const u8 = "textureSpec";
    pub const Has_Texture: [:0]const u8 = "hasTexture";

    // Vertex color uniforms
    pub const Has_Color: [:0]const u8 = "hasColor";
    pub const Has_Vertex_Colors: [:0]const u8 = "hasVertexColors";
};
