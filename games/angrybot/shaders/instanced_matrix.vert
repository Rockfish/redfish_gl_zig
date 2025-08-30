#version 400 core

// Model data
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

// Per instance transform matrix (4x4 matrix takes 4 attribute locations)
layout(location = 2) in vec4 transformRow0;
layout(location = 3) in vec4 transformRow1;
layout(location = 4) in vec4 transformRow2;
layout(location = 5) in vec4 transformRow3;

out vec2 FragTextureCoord;

// Transformation matrices
uniform mat4 projectionView;

void main() {
    // Reconstruct the transform matrix from the 4 vec4 attributes
    mat4 transform = mat4(
        transformRow0,
        transformRow1,
        transformRow2,
        transformRow3
    );

    // Apply the complete transformation: projection * view * model * vertex
    gl_Position = projectionView * transform * vec4(inPosition, 1.0);

    FragTextureCoord = inTexCoord;
}