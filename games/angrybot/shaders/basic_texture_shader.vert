#version 330 core
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

out vec2 fragTextureCoord;
out vec4 fragPosLightSpace;
out vec3 fragWorldPos;

// Transformation matrices
uniform mat4 model;
uniform mat4 projectionView;
uniform mat4 lightSpaceMatrix;

void main() {
    gl_Position = projectionView * model * vec4(inPosition, 1.0);
    fragTextureCoord = inTexCoord;
    fragWorldPos = vec3(model * vec4(inPosition, 1.0));
    fragPosLightSpace = lightSpaceMatrix * vec4(fragWorldPos, 1.0);
}
