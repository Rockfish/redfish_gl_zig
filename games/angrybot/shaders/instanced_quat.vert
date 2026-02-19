#version 400 core

// model data
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;

// Per instance data
layout(location = 2) in vec4 rotationQuat;
layout(location = 3) in vec3 positionOffset;

out vec2 fragTextureCoord;

// Transformation matrices
uniform mat4 projectionView;

vec4 hamiltonProduct(vec4 q1, const vec4 q2) {
    return vec4(
        q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y,
        q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x,
        q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w,
        q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z
    );
}

//vec4 multiplyQuaternions(vec4 q1, vec4 q2) {
//    return vec4(
//        q1.w * q2.x + q1.x * q2.w + q1.y * q2.z - q1.z * q2.y, // w
//        q1.w * q2.y - q1.x * q2.z + q1.y * q2.w + q1.z * q2.x, // x
//        q1.w * q2.z + q1.x * q2.y - q1.y * q2.x + q1.z * q2.w, // y
//        q1.w * q2.w - q1.x * q2.x - q1.y * q2.y - q1.z * q2.z // z
//    );
//}

// glm stores quat as { w, x, y, z }
// glam stores quat as { x, y, z, w }
vec4 flip(vec4 glam) {
    vec4 glm = vec4(glam.w, glam.x, glam.y, glam.z);
    return glm;
}

vec3 rotateByQuat(vec3 v, vec4 q_orig) {
    vec4 q = flip(q_orig); // flip convention;

    vec4 qPrime = vec4(-q.x, -q.y, -q.z, q.w); // this is pointless

    vec4 first = hamiltonProduct(q, vec4(v.x, v.y, v.z, 0.0));
    vec4 vPrime = hamiltonProduct(first, qPrime);

    return vec3(vPrime.x, vPrime.y, vPrime.z);
}

// Optimized quaternion rotation from Zig's quat.rotateVec()
// Uses formula: v' = v + 2 * cross(q.xyz, cross(q.xyz, v) + q.w * v)
// Expects quaternion in [x, y, z, w] format (glam convention)
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
    vec3 rotatedInPos = rotateVec(inPosition, rotationQuat);

    gl_Position = projectionView * vec4(rotatedInPos + positionOffset, 1.0);

    fragTextureCoord = inTexCoord;
}
