#version 400 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

uniform mat4 matModel;
uniform mat4 matView;
uniform mat4 matProjection;
uniform mat4 matLightSpace;

out vec3 fragPosition;
out vec2 fragTexCoord;
out vec4 fragLightSpacePosition;

void main() {
    gl_Position = matProjection * matView * matModel * vec4(inPosition, 1.0);

    fragPosition = vec3(matModel * vec4(inPosition, 1.0));
    fragTexCoord = inTexCoord;
    fragLightSpacePosition = matLightSpace * vec4(fragPosition, 1.0);
}
