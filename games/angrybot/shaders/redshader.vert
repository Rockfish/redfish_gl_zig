#version 400 core

layout(location = 0) in vec3 inPosition;

// Transformation matrices
uniform mat4 model;
uniform mat4 matProjection;
uniform mat4 matView;

void main() {
    gl_Position = matProjection * matView * model * vec4(inPosition, 1.0);
}
