#version 400 core

// model data
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;

// Per instance data
layout(location = 8) in vec4 rotationQuat;
layout(location = 9) in vec3 positionOffset;

uniform mat4 matView;
uniform mat4 matProjection;

out vec4 fragColor;
out vec2 fragTexCoord;
out vec3 fragNormal;

vec3 rotateVec(vec3 v, vec4 q) {
    float qx = q.x;
    float qy = q.y;
    float qz = q.z;
    float qw = q.w;
    float vx = v.x;
    float vy = v.y;
    float vz = v.z;

    // First cross product: cross(q.xyz, v) + q.w * v
    float cx1 = qy * vz - qz * vy + qw * vx;
    float cy1 = qz * vx - qx * vz + qw * vy;
    float cz1 = qx * vy - qy * vx + qw * vz;

    // Second cross product: cross(q.xyz, cross(q.xyz, v) + q.w * v)
    float cx2 = qy * cz1 - qz * cy1;
    float cy2 = qz * cx1 - qx * cz1;
    float cz2 = qx * cy1 - qy * cx1;

    // Final result: v + 2 * cross(q.xyz, cross(q.xyz, v) + q.w * v)
    return vec3(vx + 2.0 * cx2, vy + 2.0 * cy2, vz + 2.0 * cz2);
}

void main() {
    vec3 rotatedPos = rotateVec(inPosition, rotationQuat);
    gl_Position = matProjection * matView * vec4(rotatedPos + positionOffset, 1.0);

    fragTexCoord = inTexCoord;
    fragColor = vec4(1.0);
    fragNormal = inNormal;
}
