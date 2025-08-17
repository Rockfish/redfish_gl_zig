#version 330 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexCoord;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec4 inColor;
layout(location = 5) in ivec4 inJointIds;
layout(location = 6) in vec4 inWeights;

const int MAX_JOINTS = 100;
const int MAX_JOINT_INFLUENCE = 4;

uniform mat4 nodeTransform;
uniform mat4 jointMatrices[MAX_JOINTS];
uniform bool hasSkin;

uniform mat4 projectionView;
uniform mat4 model;
uniform mat4 aimRot;

out vec2 TexCoord;
out vec3 Norm;
out vec4 FragPosLightSpace;
out vec3 FragWorldPos;

uniform bool depth_mode;
uniform mat4 lightSpaceMatrix;

vec3 localNormal = vec3(0.0f);

vec4 get_animated_position() {
    vec4 totalPosition = vec4(0.0f);

    if (hasSkin) {
        // Use joint skinning for animated models
        for (int i = 0; i < MAX_JOINT_INFLUENCE; i++) {
            if (inJointIds[i] == -1) {
                continue;
            }

            if (inJointIds[i] >= MAX_JOINTS) {
                totalPosition = vec4(inPosition, 1.0f);
                break;
            }

            vec4 localPosition = jointMatrices[inJointIds[i]] * vec4(inPosition, 1.0f);
            totalPosition += localPosition * inWeights[i];

            localNormal = mat3(jointMatrices[inJointIds[i]]) * inNormal;
        }
    } else {
        // Use node transform for non-skinned models
        totalPosition = nodeTransform * vec4(inPosition, 1.0f);
    }

    return totalPosition;
}

void main() {
    vec4 final_position = get_animated_position();

    if (depth_mode) {
        gl_Position = lightSpaceMatrix * model * final_position;
    } else {
        gl_Position = projectionView * model * final_position;
    }

    TexCoord = inTexCoord;

    Norm = vec3(aimRot * vec4(localNormal, 1.0));
    //Norm = vec3(aimRot * vec4(inNormal, 1.0));

    FragWorldPos = vec3(model * vec4(inPosition, 1.0));

    FragPosLightSpace = lightSpaceMatrix * vec4(FragWorldPos, 1.0);
}
