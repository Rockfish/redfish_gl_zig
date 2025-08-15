# Cubic Spline Animation Support

## Overview

This document outlines the design for implementing cubic spline interpolation support in the redfish_gl_zig animation system. Cubic splines provide smooth, curved interpolation between keyframes with continuous velocity and acceleration, eliminating the jerky transitions that can occur with linear interpolation.

## Background

**What Cubic Splines Do:**
- Create smooth curves between control points using cubic polynomials
- Ensure C² continuity (position, velocity, and acceleration are continuous)
- Each curve segment is defined by: start point, start tangent, end tangent, end point
- Produce natural, fluid motion without sharp changes in direction or speed

**Usage in Game Engines:**
- Very common - industry standard in Unity, Unreal, Godot, CryEngine
- Official interpolation mode in glTF 2.0 specification (CUBICSPLINE)
- Essential for high-quality character animation, camera movement, and UI transitions

## Design Principles

1. **Plain objects** without methods - data structures are simple containers
2. **Separate structs** for different interpolation types (linear vs cubic)
3. **Simple functions** that test data type and dispatch to appropriate helpers
4. **Clear separation** between data structures and algorithms
5. **Clarity over micro-optimization** - use arrays of structs for spline data

## Data Structure Design

### Cubic Spline Keyframe Structures

```zig
/// A single cubic spline keyframe for Vec3 data
pub const Vec3CubicKeyframe = struct {
    in_tangent: Vec3,
    value: Vec3,
    out_tangent: Vec3,
};

/// A single cubic spline keyframe for Quat data
pub const QuatCubicKeyframe = struct {
    in_tangent: Quat,
    value: Quat,
    out_tangent: Quat,
};

/// A single cubic spline keyframe for scalar data
pub const ScalarCubicKeyframe = struct {
    in_tangent: f32,
    value: f32,
    out_tangent: f32,
};
```

### Linear Interpolation Data Structures

```zig
/// Linear/step interpolation data for Vec3 values
pub const Vec3LinearData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    values: []const Vec3,
};

/// Linear/step interpolation data for Quat values
pub const QuatLinearData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    values: []const Quat,
};

/// Linear/step interpolation data for scalar values
pub const ScalarLinearData = struct {
    interpolation: gltf_types.Interpolation,
    keyframe_times: []const f32,
    values: []const f32,
};
```

### Cubic Spline Data Structures

```zig
/// Cubic spline data for Vec3 values (translation/scale)
pub const Vec3CubicData = struct {
    interpolation: gltf_types.Interpolation, // Must be .cubic_spline
    keyframe_times: []const f32,
    keyframes: []const Vec3CubicKeyframe,    // Same length as keyframe_times
};

/// Cubic spline data for Quat values (rotation)
pub const QuatCubicData = struct {
    interpolation: gltf_types.Interpolation, // Must be .cubic_spline
    keyframe_times: []const f32,
    keyframes: []const QuatCubicKeyframe,    // Same length as keyframe_times
};

/// Cubic spline data for scalar values (weights)
pub const ScalarCubicData = struct {
    interpolation: gltf_types.Interpolation, // Must be .cubic_spline
    keyframe_times: []const f32,
    keyframes: []const ScalarCubicKeyframe,  // Same length as keyframe_times
};
```

### Animation Data Unions

```zig
/// Translation animation data - plain object
pub const NodeTranslationData = union(enum) {
    linear: Vec3LinearData,
    cubic_spline: Vec3CubicData,
};

/// Rotation animation data - plain object
pub const NodeRotationData = union(enum) {
    linear: QuatLinearData,
    cubic_spline: QuatCubicData,
};

/// Scale animation data - plain object
pub const NodeScaleData = union(enum) {
    linear: Vec3LinearData,
    cubic_spline: Vec3CubicData,
};

/// Weight animation data - plain object
pub const NodeWeightData = union(enum) {
    linear: ScalarLinearData,
    cubic_spline: ScalarCubicData,
};
```

### Updated NodeAnimationData

```zig
/// Node animation data - plain object
pub const NodeAnimationData = struct {
    node_id: u32,
    translation: ?NodeTranslationData,
    rotation: ?NodeRotationData,
    scale: ?NodeScaleData,
    weights: ?NodeWeightData,
};
```

## Function Design

### Type Testing and Dispatch Functions

```zig
/// Get animated translation value - tests data type and calls appropriate helper
fn getAnimatedTranslation(translation_data: ?NodeTranslationData, current_time: f32) ?Vec3 {
    if (translation_data) |data| {
        return switch (data) {
            .linear => |linear_data| interpolateVec3Linear(linear_data, current_time),
            .cubic_spline => |cubic_data| interpolateVec3Cubic(cubic_data, current_time),
        };
    }
    return null;
}

/// Get animated rotation value - tests data type and calls appropriate helper
fn getAnimatedRotation(rotation_data: ?NodeRotationData, current_time: f32) ?Quat {
    if (rotation_data) |data| {
        return switch (data) {
            .linear => |linear_data| interpolateQuatLinear(linear_data, current_time),
            .cubic_spline => |cubic_data| interpolateQuatCubic(cubic_data, current_time),
        };
    }
    return null;
}

/// Get animated scale value - tests data type and calls appropriate helper
fn getAnimatedScale(scale_data: ?NodeScaleData, current_time: f32) ?Vec3 {
    if (scale_data) |data| {
        return switch (data) {
            .linear => |linear_data| interpolateVec3Linear(linear_data, current_time),
            .cubic_spline => |cubic_data| interpolateVec3Cubic(cubic_data, current_time),
        };
    }
    return null;
}
```

### Interpolation Implementation

```zig
/// Linear/step interpolation for Vec3
fn interpolateVec3Linear(data: Vec3LinearData, current_time: f32) Vec3 {
    const keyframe_info = findKeyframeIndices(data.keyframe_times, current_time);
    return interpolateVec3(
        data.values,
        keyframe_info.start_index,
        keyframe_info.end_index,
        keyframe_info.factor,
        data.interpolation,
    );
}

/// Cubic spline interpolation for Vec3 - clean and clear!
fn interpolateVec3Cubic(data: Vec3CubicData, current_time: f32) Vec3 {
    const keyframe_info = findKeyframeIndices(data.keyframe_times, current_time);
    
    if (keyframe_info.start_index == keyframe_info.end_index) {
        return data.keyframes[keyframe_info.start_index].value;
    }
    
    const t = keyframe_info.factor;
    
    // Much clearer access to spline data!
    const start_keyframe = data.keyframes[keyframe_info.start_index];
    const end_keyframe = data.keyframes[keyframe_info.end_index];
    
    const p0 = start_keyframe.value;
    const m0 = start_keyframe.out_tangent;
    const p1 = end_keyframe.value;
    const m1 = end_keyframe.in_tangent;
    
    // Hermite interpolation
    const t2 = t * t;
    const t3 = t2 * t;
    const h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    const h10 = t3 - 2.0 * t2 + t;
    const h01 = -2.0 * t3 + 3.0 * t2;
    const h11 = t3 - t2;
    
    const dt = data.keyframe_times[keyframe_info.end_index] - 
               data.keyframe_times[keyframe_info.start_index];
    
    return p0.mulScalar(h00)
        .add(&m0.mulScalar(h10 * dt))
        .add(&p1.mulScalar(h01))
        .add(&m1.mulScalar(h11 * dt));
}

/// Cubic spline interpolation for scalars
fn interpolateScalarCubic(data: ScalarCubicData, current_time: f32) f32 {
    const keyframe_info = findKeyframeIndices(data.keyframe_times, current_time);
    
    if (keyframe_info.start_index == keyframe_info.end_index) {
        return data.keyframes[keyframe_info.start_index].value;
    }
    
    const t = keyframe_info.factor;
    
    const start_keyframe = data.keyframes[keyframe_info.start_index];
    const end_keyframe = data.keyframes[keyframe_info.end_index];
    
    const p0 = start_keyframe.value;
    const m0 = start_keyframe.out_tangent;
    const p1 = end_keyframe.value;
    const m1 = end_keyframe.in_tangent;
    
    // Hermite interpolation for scalars
    const t2 = t * t;
    const t3 = t2 * t;
    const h00 = 2.0 * t3 - 3.0 * t2 + 1.0;
    const h10 = t3 - 2.0 * t2 + t;
    const h01 = -2.0 * t3 + 3.0 * t2;
    const h11 = t3 - t2;
    
    const dt = data.keyframe_times[keyframe_info.end_index] - 
               data.keyframe_times[keyframe_info.start_index];
    
    return p0 * h00 + m0 * (h10 * dt) + p1 * h01 + m1 * (h11 * dt);
}
```

## Benefits of This Design

1. **Crystal Clear Intent**: `keyframe.value`, `keyframe.in_tangent`, `keyframe.out_tangent` is immediately understandable

2. **Easy Debugging**: You can easily inspect individual keyframes in a debugger

3. **Type Safety**: The compiler ensures you're accessing the right fields

4. **Self-Documenting**: The code explains what each piece of data represents

5. **Easier Data Construction**: When parsing glTF data, you can build keyframes one at a time:
```zig
const keyframe = Vec3CubicKeyframe{
    .in_tangent = parsed_in_tangent,
    .value = parsed_value,
    .out_tangent = parsed_out_tangent,
};
```

6. **Memory Layout Still Efficient**: The structs pack nicely and cache behavior is still good

7. **Extensible**: Easy to add new interpolation types by extending the unions

## Implementation Notes

### Quaternion Cubic Splines
Quaternion cubic spline interpolation requires special handling:
- Quaternion tangents must be properly normalized
- May need to use specialized quaternion spline algorithms (Squad, etc.)
- Initial implementation can fall back to spherical linear interpolation (slerp)

### glTF Data Layout
The glTF specification stores cubic spline data in a flat array:
`[in_tangent0, value0, out_tangent0, in_tangent1, value1, out_tangent1, ...]`

This needs to be converted to our keyframe struct arrays during parsing.

### Performance Considerations
- The struct-based approach has slight memory overhead vs flat arrays
- Cache performance is still good since related data is accessed together
- Clarity and maintainability benefits outweigh small performance costs
- Can optimize later if profiling shows bottlenecks

## Integration Points

1. **glTF Parser**: Update to recognize CUBICSPLINE interpolation and build appropriate data structures
2. **Animation Preprocessing**: Convert flat glTF arrays to keyframe structs
3. **Existing Animation Functions**: Update `getAnimatedTransform` to use new dispatch functions
4. **Testing**: Create test cases with various cubic spline scenarios

## Future Enhancements

- Implement full quaternion cubic spline interpolation (Squad)
- Add support for additional spline types (Catmull-Rom, B-splines)
- Optimize memory layout if performance profiling indicates issues
- Add spline editing/creation tools for development