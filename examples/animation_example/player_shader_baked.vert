#version 410 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec4 inColor;
layout(location = 5) in ivec4 inJointIds;
layout(location = 6) in vec4 inWeights;

const int MAX_JOINTS = 100;
const int MAX_JOINT_INFLUENCE = 4;

uniform bool hasSkin;
uniform int numMeshes;
uniform int numJoints;
uniform int meshID;
uniform int frameID;

int animationID = 0;
// Instance ID: gl_InstanceID

uniform samplerBuffer animationData;
uniform samplerBuffer modelMatrixes;

uniform mat4 matProjection;
uniform mat4 matView;
uniform mat4 matModel;
uniform mat4 matLightSpace;

out vec2 fragTexCoord;
out vec3 fragNormal;
out vec4 fragColor;
out vec4 fragPosLightSpace;
out vec3 fragWorldPos;

mat4 fetchMatrix(samplerBuffer data, int index) {
    vec4 col1 = texelFetch(data, index * 4 + 0);
    vec4 col2 = texelFetch(data, index * 4 + 1);
    vec4 col3 = texelFetch(data, index * 4 + 2);
    vec4 col4 = texelFetch(data, index * 4 + 3);
    return mat4(col1, col2, col3, col4);
}

void main() {
    vec4 totalPosition = vec4(0.0f);
    vec3 totalNormal = vec3(0.0f);

    int frameSize = (numMeshes + numJoints);
    int frameOffset = frameID * frameSize;
    int jointOffset = frameOffset + numMeshes;

    if (hasSkin) {

        // Use joint skinning for animated models
        for (int i = 0; i < MAX_JOINT_INFLUENCE; i++) {
            if (inJointIds[i] == -1) {
                continue;
            }

            if (inJointIds[i] >= MAX_JOINTS) {
                totalPosition = vec4(inPosition, 1.0f);
                totalNormal = inNormal;
                break;
            }

            mat4 jointMatrix = fetchMatrix(animationData, jointOffset + inJointIds[i]);

            vec4 localPosition = jointMatrix * vec4(inPosition, 1.0f);
            totalPosition += localPosition * inWeights[i];

            vec3 localNormal = mat3(jointMatrix) * inNormal;
            totalNormal += localNormal * inWeights[i];
        }
    } else {
        // Use node transform for non-skinned models
        mat4 nodeTransform = fetchMatrix(animationData, frameOffset + meshID);
        totalPosition = nodeTransform * vec4(inPosition, 1.0f);
        totalNormal = mat3(nodeTransform) * inNormal;
    }

    mat4 modelTransform = fetchMatrix(modelMatrixes, gl_InstanceID);

    gl_Position = matProjection * matView * modelTransform * totalPosition;

    fragTexCoord = inTexCoord;
    fragColor = inColor;

    // Derive the normal matrix from this instance's transform, not the shared
    // matModel uniform — each instance has its own modelTransform.
    mat3 matNormal = transpose(inverse(mat3(modelTransform)));
    fragNormal = normalize(matNormal * totalNormal);

    fragWorldPos = vec3(modelTransform * totalPosition);
    fragPosLightSpace = matLightSpace * vec4(fragWorldPos, 1.0);
}
