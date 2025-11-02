#version 400 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec4 inColor;
layout(location = 5) in ivec4 inJointIds;
layout(location = 6) in vec4 inWeights;

uniform mat4 matModel;
uniform mat4 matView;
uniform mat4 matProjection;

out vec2 fragTexCoord;
out vec3 fragNormal;

void main()
{
    fragTexCoord = vertTexCoord;
    gl_Position = matProjection * matView * matModel * vec4(inPosition, 1.0);

    mat4 matNormal = transpose(inverse(matModel));
    fragNormal = normalize(vec3(matNormal * vec4(inNormal, 1.0)));
}