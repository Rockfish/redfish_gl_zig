#version 400 core

// For location values see src/core/constants.zig
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;

layout(location = 7) in mat4 instanceTransform;

// Transformation matrices
uniform mat4 projectionView;

out vec4 fragColor;
out vec2 fragTexCoord;
out vec3 fragNormal;

void main() {
    gl_Position = projectionView * instanceTransform * vec4(inPosition, 1.0);

    fragTexCoord = inTexCoord;
    fragColor = vec4(1.0);
    fragNormal = inNormal;
}