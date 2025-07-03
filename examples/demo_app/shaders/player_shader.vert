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

uniform mat4 matProjection;
uniform mat4 matView;
uniform mat4 matModel;
uniform mat4 matLightSpace;

out vec2 fragTexCoord;
out vec3 fragNormal;
out vec4 fragColor;
out vec4 fragPosLightSpace;
out vec3 fragWorldPos;

void main() {
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

            vec3 localNormal = mat3(jointMatrices[inJointIds[i]]) * inNormal;
        }
    } else {
        // Use node transform for non-skinned models
        totalPosition = nodeTransform * vec4(inPosition, 1.0f);
    }

    gl_Position = matProjection * matView * matModel * totalPosition;

    fragTexCoord = inTexCoord;
    fragColor = inColor;

    mat4 matNormal = transpose(inverse(matModel));
    fragNormal = normalize(vec3(matNormal * vec4(inNormal, 1.0)));

    fragWorldPos = vec3(matModel * vec4(inPosition, 1.0));
    fragPosLightSpace = matLightSpace * vec4(fragWorldPos, 1.0);
}
