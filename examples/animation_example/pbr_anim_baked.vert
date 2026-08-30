#version 410 core

// Input attributes
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexCoord;
layout(location = 3) in vec3 inTangent;
layout(location = 4) in vec4 inColor;
layout(location = 5) in ivec4 inJointIds;
layout(location = 6) in vec4 inWeights;

const int MAX_JOINTS = 100;
const int MAX_JOINT_INFLUENCE = 4;

// Texture buffers
uniform samplerBuffer animationData;
uniform samplerBuffer modelMatrixes;

// Uniforms
uniform mat4 matProjection;
uniform mat4 matView;
uniform mat4 matModel;

uniform bool hasSkin;

// Outputs to the fragment shader
out vec3 fragWorldPosition;
out vec2 fragTexCoord;
out vec3 fragTangent;
out vec4 fragColor;
out vec3 fragNormal;
out mat3 fragTBN;

mat4 fetchMatrix(samplerBuffer data, int index) {
    vec4 col1 = texelFetch(data, index * 4 + 0);
    vec4 col2 = texelFetch(data, index * 4 + 1);
    vec4 col3 = texelFetch(data, index * 4 + 2);
    vec4 col4 = texelFetch(data, index * 4 + 3);
    return mat4(col1, col2, col3, col4);
}

void main() {
    vec4 totalPosition = vec4(0.0);
    vec3 totalNormal = vec3(0.0);
    vec3 totalTangent = vec3(0.0);

    if (hasSkin) {
        // Use joint skinning for animated models
        for (int i = 0; i < MAX_JOINT_INFLUENCE; i++) {
            if (inJointIds[i] == -1) {
                continue;
            }

            if (inJointIds[i] >= MAX_JOINTS) {
                totalPosition = vec4(inPosition, 1.0);
                totalNormal = inNormal;
                totalTangent = inTangent;
                break;
            }

            mat4 jointMatrix = fetchMatrix(animationData, jointOffset + inJointIds[i]);
            vec4 localPosition = jointMatrix * vec4(inPosition, 1.0);
            totalPosition += localPosition * inWeights[i];

            vec3 localNormal = mat3(jointMatrix) * inNormal;
            totalNormal += localNormal * inWeights[i];

            vec3 localTangent = mat3(jointMatrix) * inTangent;
            totalTangent += localTangent * inWeights[i];
        }
    } else {
        // Use node transform for non-skinned models
        totalPosition = nodeTransform * vec4(inPosition, 1.0);
        totalNormal = inNormal;
        totalTangent = inTangent;
    }

    mat4 modelTransform = fetchMatrix(modelMatrixes, gl_InstanceID);

    // Compute the normal matrix from the model matrix for correct normal transformation.
    mat3 normalMatrix = transpose(inverse(mat3(modelTransform)));

    // Transform the normal and tangent into world space.
    vec3 N = normalize(normalMatrix * totalNormal);
    vec3 T = normalize(normalMatrix * totalTangent);

    // Re-orthogonalize the tangent relative to the normal.
    T = normalize(T - dot(T, N) * N);

    // Compute the bitangent using the cross product.
    vec3 B = cross(N, T);

    // Compute the world-space position.
    vec4 worldPos = modelTransform * totalPosition;
    fragWorldPosition = worldPos.xyz;

    // Pass through texture coordinates and vertex color.
    fragTexCoord = inTexCoord;
    fragColor = inColor;

    // Output the transformed normal.
    fragNormal = N;

    // Construct the TBN matrix to transform normals from tangent space to world space.
    fragTBN = mat3(T, B, N);

    // Compute the final vertex position in clip space.
    gl_Position = matProjection * matView * modelTransform * totalPosition;
}
