#version 400 core

layout(location = 0) in vec3 inPosition;

// Transformation matrices
uniform mat4 model;
uniform mat4 projectionView;

void main() {
    gl_Position = projectionView * model * vec4(inPosition, 1.0);
}
