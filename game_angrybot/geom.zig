const std = @import("std");
const math = @import("math");

const Vec3 = math.Vec3;
const vec3 = math.vec3;
const Mat3 = math.Mat3;
const mat3 = math.mat3;

pub fn distanceBetweenPointAndLineSegment(point: *const Vec3, a: *const Vec3, b: *const Vec3) f32 {
    const ab = b.sub(a);
    const ap = point.sub(a);
    if (ap.dot(&ab) <= 0.0) {
        return ap.length();
    }
    const bp = point.sub(b);
    if (bp.dot(&ab) >= 0.0) {
        return bp.length();
    }
    return ab.cross(&ap).length() / ab.length();
}

pub fn distanceBetweenLineSegments(a0: *const Vec3, a1: *const Vec3, b0: *const Vec3, b1: *const Vec3) f32 {
    const eps: f32 = 0.001;

    var a = a1.sub(a0);
    var b = b1.sub(b0);
    const mag_a = a.length();
    const mag_b = b.length();

    a = a.divScalar(mag_a);
    b = b.divScalar(mag_b);

    const cross = a.cross(&b);
    const cl = cross.length();
    const denom = cl * cl;

    // If lines are parallel (denom=0) test if lines overlap.
    // If they don't overlap then there is a closest point solution.
    // If they do overlap, there are infinite closest positions, but there is a closest distance
    if (denom < eps) {
        const d0 = a.dot(&b0.sub(a0));
        const d1 = a.dot(&b1.sub(a0));

        // Is segment B before A?
        if (d0 <= 0.0 and 0.0 >= d1) {
            if (@abs(d0) < @abs(d1)) {
                return a0.sub(b0).length();
            }
            return a0.sub(b1).length();
        } else if (d0 >= mag_a and mag_a <= d1) {
            if (@abs(d0) < @abs(d1)) {
                return a1.sub(b0).length();
            }
            return a1.sub(b1).length();
        }

        // Segments overlap, return distance between parallel segments
        return a.mulScalar(d0).add(a0).sub(b0).length();
    }

    // Lines criss-cross: Calculate the projected closest points
    const t = b0.sub(a0);
    const det_a = mat3(t, b, cross).determinant();
    const det_b = mat3(t, a, cross).determinant();

    const t0 = det_a / denom;
    const t1 = det_b / denom;

    var p_a = a0.add(&a.mulScalar(t0)); // Projected closest point on segment A
    var p_b = b0.add(&b.mulScalar(t1)); // Projected closest point on segment B

    // Clamp projections
    if (t0 < 0.0) {
        p_a = a0.*;
    } else if (t0 > mag_a) {
        p_a = a1.*;
    }

    if (t1 < 0.0) {
        p_b = b0.*;
    } else if (t1 > mag_b) {
        p_b = b1.*;
    }

    // Clamp projection A
    if (t0 < 0.0 or t0 > mag_a) {
        var dot = b.dot(&p_a.sub(b0));
        dot = clamp(dot, 0.0, mag_b);
        p_b = b0.add(&b.mulScalar(dot));
    }

    // Clamp projection B
    if (t1 < 0.0 or t1 > mag_b) {
        var dot = a.dot(&p_b.sub(a0));
        dot = clamp(dot, 0.0, mag_a);
        p_a = a0.add(&a.mulScalar(dot));
    }

    return p_a.sub(&p_b).length();
}

/// See https://github.com/icaven/glm/blob/master/glm/gtx/vector_angle.inl
pub fn orientedAngle(x: *const Vec3, y: *const Vec3, ref_axis: *const Vec3) f32 {

    const angle = math.radiansToDegrees(math.acos(x.dot(y)));

    if (ref_axis.dot(&x.cross(y)) < 0.0) {
        return -angle;
    } else {
        return angle;
    }
}

// static inline SIMD_CFUNC simd_float2 simd_mix(simd_float2 x, simd_float2 y, simd_float2 t) {
//   return x + t*(y - x);
// }

pub fn clamp(num: f32, min: f32, max: f32) f32 {
    var val = num;
    // assert!(min <= max, "min > max, or either was NaN. min = {min:?}, max = {max:?}");
    if (val < min) {
        val = min;
    }
    if (val > max) {
        val = max;
    }
    return val;
}
