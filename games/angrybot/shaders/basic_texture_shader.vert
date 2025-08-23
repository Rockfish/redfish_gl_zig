#version 330 core
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

out vec2 FragTextureCoord;
out vec4 FragPosLightSpace;
out vec3 FragWorldPos;

// Transformation matrices
uniform mat4 model;
uniform mat4 projectionView;
uniform mat4 lightSpaceMatrix;

void main() {
    gl_Position = projectionView * model * vec4(inPosition, 1.0);
    FragTextureCoord = inTexCoord;
    FragWorldPos = vec3(model * vec4(inPosition, 1.0));
    FragPosLightSpace = lightSpaceMatrix * vec4(FragWorldPos, 1.0);
}
