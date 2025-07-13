#version 330 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexCoord;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec3 inBiTangent;
layout(location = 5) in ivec4 inJointIds;
layout(location = 6) in vec4 inWeights;

const int MAX_JOINTS = 100;
const int MAX_JOINT_INFLUENCE = 4;

uniform mat4 jointMatrices[MAX_JOINTS];
uniform mat4 nodeTransform;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

out vec2 fragTexCoord;
out vec3 fragNormal;
out vec4 fragPosLightSpace;
out vec3 fragWorldPos;

// player Transformation matrices
uniform mat4 aimRot;
uniform mat4 lightSpaceMatrix;

void main() {
    vec4 totalPosition = vec4(0.0f);

    for (int i = 0; i < MAX_JOINT_INFLUENCE; i++)
    {
        if (inJointIds[i] == -1) {
            continue;
        }

        if (inJointIds[i] >= MAX_JOINTS) {
            totalPosition = vec4(inPosition, 1.0f);
            break;
        }

        vec4 localPosition = jointMatrices[inJointIds[i]] * vec4(inPosition, 1.0f);
        totalPosition += localPosition * inWeights[i];

        vec3 localNormal = mat3(jointMatrices[inJointIds[i]]) * inNormal;
    }

    // This would work if the inJointIds has zeros instead of -1
    // vec4 skinMatrix = inWeights[0] * jointMatrices[inJointIds[0]] +
    //                   inWeights[1] * jointMatrices[inJointIds[1]] +
    //                   inWeights[2] * jointMatrices[inJointIds[2]] +
    //                   inWeights[3] * jointMatrices[inJointIds[3]];
    // totalPosition = skinMatrix * vec4(inPosition, 1.0f);

    if (totalPosition == vec4(0.0f)) {
        totalPosition = nodeTransform * vec4(inPosition, 1.0f);
    }

    gl_Position = projection * view * model * totalPosition;

    fragTexCoord = inTexCoord;

    fragNormal = vec3(aimRot * vec4(inNormal, 1.0));

    fragWorldPos = vec3(model * vec4(inPosition, 1.0));

    fragPosLightSpace = lightSpaceMatrix * vec4(fragWorldPos, 1.0);
}
