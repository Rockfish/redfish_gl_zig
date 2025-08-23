#version 330 core
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

out vec2 FragTextureCoord;

// Transformation matrices
uniform mat4 model;
uniform mat4 projectionView;

void main() {
    gl_Position = projectionView * model * vec4(inPosition, 1.0);
    FragTextureCoord = inTexCoord;
}
