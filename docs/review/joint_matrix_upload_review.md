# Joint-Matrix Upload Review — 2026-08-15

Question under discussion: is one `glUniformMatrix4fv` per array slot
(`src/core/model.zig` `Model.draw`, ~100 calls per skinned model) the only
legal way, under GLSL 4.10 / OpenGL 4.0–4.1, to feed
`uniform mat4 jointMatrices[MAX_JOINTS]`? And if hundreds of instances of
the same mesh need different poses, is a texture the right next step — or
does reading floats from a texture force normalization?

Prompted by a full read of the GLSL 4.10 Specification and by the
animation-texture approach mentioned in a video.

No code changes in this note.

---

## TL;DR

The 100-call loop is a **wrapper choice**, not a language or API
requirement. The GLSL spec describes how the shader *declares and
indexes* a uniform array. The **OpenGL API** spec describes how the
host writes it, and that API has taken a count since OpenGL 2.0:

```
glUniformMatrix4fv(location_of_jointMatrices, 100, GL_FALSE, first_float);
```

That is one call for the whole palette. `Mat4` is already an
`extern struct` of 16 tightly packed `f32`s, and
`Animator.joint_matrices` is a contiguous `[MAX_JOINTS]Mat4`, so the
bytes are already in the layout that call wants.

That cheap fix does **not** get you hundreds of independently posed
instances in one draw. Default-block uniforms are per-program state:
every instance still needs its own upload + draw (or a different
binding). For that scale, still on GL 4.0/4.1, the options are:

| Path | GL / GLSL | Good for | Blocker at 100s of instances |
|------|-----------|----------|------------------------------|
| One `glUniformMatrix4fv` with `count = N` | 2.0 / 1.10 | one (or a few) characters | still one upload+draw per unique pose |
| Uniform buffer (`std140` block) | 3.1 / 1.40 | one palette, cheap rebind | `MAX_UNIFORM_BLOCK_SIZE` is only guaranteed 16 KiB (~256 mat4s) |
| Texture buffer (`samplerBuffer` + `RGBA32F`) | 3.1 / 1.40 | many unique poses, one instanced draw | none at hundreds; this is the GL 4.1 tool |
| 2D float texture (`texelFetch` + `RGBA32F`) | 3.0 / 1.30 | baked clips *or* a pose atlas | same; this is the video technique |
| SSBO | **4.3 / 4.30** | huge structured arrays | **not in 4.1** |

**Textures do not have to normalize.** Normalization is a property of
the *internal format*, not of "reading a texture." `GL_RGBA8` /
`GL_RGBA` normalize to `[0,1]`. `GL_RGBA32F` and `GL_RGBA16F` return
the stored floats unchanged. `texelFetch` then reads them at integer
texel coordinates with no filtering. That is why the video works for
skinning matrices.

Recommended ladder, when this becomes a plan:

1. **Now (same shader):** one `glUniformMatrix4fv` for
   `jointMatrices[0]` with `count = MAX_JOINTS`. Cache that one
   location. Drop the `bufPrintZ("jointMatrices[{d}]", i)` loop.
2. **A handful of characters:** move the palette into a `std140` UBO
   and `glBindBufferRange` per draw. Frees default-block uniform
   components (100 mat4s is already over the spec-minimum vertex
   uniform budget).
3. **Hundreds of instances:** one `RGBA32F` texture buffer or 2D
   texture holding every instance's palette (or every baked clip
   frame), one `glDrawElementsInstanced`. Instance id selects the
   row; joint id selects the columns.

---

## What the GLSL 4.10 spec actually covers

GLSL 4.10 is the *shading language*. For this problem it specifies:

- `uniform mat4 jointMatrices[100];` is a default-block uniform array
  (ch. 4, Uniforms).
- Dynamic indexing (`jointMatrices[inJointIds[i]]`) is legal in the
  vertex stage.
- Uniform *blocks* (`uniform JointBlock { ... };`) and `std140`
  layout (ch. 4.3.7 / 7.6.2) — the language side of UBOs.
- Samplers, `texelFetch`, `samplerBuffer`, and floating-point texture
  lookups (ch. 8.7–8.9).

It does **not** specify `glUniform*`. Host upload lives in the OpenGL
4.0 / 4.1 API specification (and the `glUniform` reference page).
Reading only GLSL, "one name per array element" looks like the whole
story because that is how the shader *mentions* elements. The API has
always treated the array as one uniform whose first-element location
accepts a count.

Two easy traps that follow from that split:

- Sequential elements do **not** have sequential locations. You cannot
  take `loc(jointMatrices[0])` and add `i`. Either query each name, or
  pass `count > 1` at the first element's location. The current loop
  does the first; the API prefers the second.
- `glGetUniformLocation(program, "jointMatrices")` and
  `"jointMatrices[0]"` are both defined to return the first element.
  That is the location the count-form call uses.

---

## Current cost in this tree

`Model.draw` (`src/core/model.zig`) for every skinned draw:

1. Formats `"jointMatrices[0]"` … `"jointMatrices[99]"` with
   `bufPrintZ`.
2. Looks each name up in `Shader.locations` (and on first use calls
   `glGetUniformLocation` 100 times).
3. `setMat4` → `useShader()` + `glUniformMatrix4fv(..., count = 1, ...)`.
4. Copies each `Mat4` onto the stack (`const joint_transform = ...`)
   before taking its address.

`Animator.joint_matrices` is already `[MAX_JOINTS]Mat4` and `Mat4` is
column-major, 64 bytes, no padding — the same layout
`glUniformMatrix4fv` with `transpose = GL_FALSE` expects. The
contiguous upload is a pointer + a count, not a packing problem.

`Shader.setMat4` hard-codes `count = 1`. There is no
`setMat4Array` today. That is why the loop exists.

---

## Path 1 — same declaration, one API call

OpenGL 4.1 `glUniform` / `UniformMatrix4fv`:

> For the matrix commands, `count` is the number of matrices to
> modify. This should be 1 if the targeted uniform is not an array of
> matrices, and 1 or more if it is.

Host sketch (not applied):

```zig
const loc = shader.getUniformLocation("jointMatrices", {});
gl.uniformMatrix4fv(
    loc,
    @intCast(constants.MAX_JOINTS),
    gl.FALSE,
    @ptrCast(&self.animator.joint_matrices),
);
```

Shader is unchanged: `uniform mat4 jointMatrices[MAX_JOINTS];`.

This is the right first move. It does not change the instancing
story: default-block uniforms are program state, so instance B
overwrites instance A's palette. Hundreds of unique poses still mean
hundreds of uploads and hundreds of draws.

### Uniform-component budget

OpenGL 4.0/4.1 minimum `MAX_VERTEX_UNIFORM_COMPONENTS` is **1024**.
A `mat4` is 16 components. `jointMatrices[100]` is **1600**, before
`matProjection` / `matView` / `matModel` / `nodeTransform` /
`matLightSpace`. Desktop NVIDIA/AMD/Intel (and macOS GL 4.1) typically
report 4096+, which is why 100 joints compiles here. It is not
portable to a spec-minimum vertex stage, and it is the reason a UBO
is the better home even for a single character.

This machine was measured 2026-08-16 (`zig build gl_caps-run`):
**4096** components, so 100 mat4s fit with 2496 left. The spec-minimum
scare is not the local constraint. See [Measured caps](#measured-caps-this-mac)
for the rest.

---

## Path 2 — uniform buffer (GL 3.1, already in 4.1)

GLSL 4.10 uniform blocks:

```glsl
#version 400 core
layout(std140) uniform JointBlock {
    mat4 jointMatrices[MAX_JOINTS];
};
```

`std140` rules for a column-major `mat4`: four `vec4` columns, each
16-byte aligned, so one matrix is 64 bytes and an array of them is
tightly packed. That matches `Mat4` / `[MAX_JOINTS]Mat4`. One
`glBufferSubData` (or a persistently mapped buffer) replaces the
uniform calls. Bind with `glBindBufferBase` /
`glBindBufferRange`.

`MAX_UNIFORM_BLOCK_SIZE` minimum is **16384 bytes** = 256 mat4s.
One character (100 × 64 = 6400 bytes) fits. A few packed palettes
fit. Hundreds of palettes do **not** fit in one block on min-spec,
and often not on desktop either (64 KiB is a common cap → ~10
palettes of 100 joints).

So a UBO is:

- The right upgrade for "several characters, one draw each."
- A way to stop eating the default-block component budget.
- Not the crowd / instancing solution, unless you batch by "how
  many palettes fit in one bind" and pass a per-instance palette
  offset — still a small multiple, not hundreds.

---

## Path 3 — textures, and the normalization question

The video is almost certainly this technique. It is valid in GLSL
4.10. Normalization is the usual objection and it is a format
mix-up.

### What actually normalizes

| Internal format | What `texelFetch` / `texture` return |
|-----------------|--------------------------------------|
| `GL_RGBA`, `GL_RGBA8`, `GL_RGB8` | unsigned-normalized `[0, 1]` |
| `GL_RGBA8_SNORM` | signed-normalized `[-1, 1]` |
| `GL_RGBA16F`, `GL_RGBA32F` | the stored floats, unchanged |
| `GL_RGBA32I` / `GL_RGBA32UI` | integers (`isampler*` / `usampler*`) |

The GLSL 4.10 texture-lookup chapter says floating-point textures
return their values as-is. Unsigned normalized formats are the
ones mapped to `[0, 1]`. Skinning matrices want **`GL_RGBA32F`**
(or `GL_RGBA16F` if you accept ~3–4 decimal digits — usually too
thin once translation is in the matrix).

`texture()` also applies wrap/filter and takes normalized `[0,1]`
*coordinates*. For matrices use **`texelFetch`**: integer texel
coordinates, no filter, exact texel. Set `GL_TEXTURE_MIN_FILTER`
/ `MAG_FILTER` to `GL_NEAREST` if anything ever samples it with
`texture()`.

sRGB formats also convert. Do not store palettes in sRGB.

### 3a. Texture buffer (`samplerBuffer`)

GL 3.1. A 1D buffer of texels, addressed by integer index. Natural
fit for "array of vec4 columns."

```glsl
uniform samplerBuffer jointTex; // bound as RGBA32F
uniform int paletteOffset;      // instance_id * joints * 4

mat4 fetchJoint(int joint) {
    int base = paletteOffset + joint * 4;
    return mat4(
        texelFetch(jointTex, base + 0),
        texelFetch(jointTex, base + 1),
        texelFetch(jointTex, base + 2),
        texelFetch(jointTex, base + 3)
    );
}
```

Host: `glTexBuffer(GL_TEXTURE_BUFFER, GL_RGBA32F, vbo)`. Upload with
`glBufferSubData` on that buffer — same as any other VBO.

`MAX_TEXTURE_BUFFER_SIZE` minimum is **65536 texels**. Each joint is
4 texels (4 columns). 100 joints = 400 texels. Min-spec holds
`65536 / 400 ≈ 163` full palettes; real drivers are orders of
magnitude larger. Hundreds of unique poses in one buffer is
comfortable.

This is the GL 4.1 answer to "many instances, each with its own
evaluated pose, one instanced draw."

### 3b. 2D float texture (the usual video)

Two layouts, both `GL_RGBA32F`, both `texelFetch(..., lod = 0)`:

**Pose atlas (upload every frame).**
Width = `MAX_JOINTS * 4` texels (one matrix = four RGBA pixels).
Height = instance count. Row `gl_InstanceID` is that instance's
palette. CPU still runs `Animator` per instance; the GPU just
reads the results without a uniform round-trip per draw.

**Baked clip sheet (upload once).**
Width = joints × 4. Height = sampled frames of a clip (or stacked
clips). Each instance only carries a clip id, a time (or two frame
indices + a lerp). The CPU animator goes away for simple playback.
This is what most "we put animation in a texture" talks mean, and
it is the right path when hundreds of instances share a few clips
and only differ by phase.

Frame interpolation: fetch two adjacent rows and lerp the matrices
(or, better, lerp the underlying TRS and rebuild — lerp of matrices
is an approximation). Do not rely on `GL_LINEAR` across a matrix
stored as four pixels; the four columns would filter independently
and produce a garbage matrix.

---

## Path 4 — not available on 4.1

**SSBO** (`layout(std430) buffer`) is OpenGL 4.3 / GLSL 4.30. It is
the modern "just put a huge array of structs in a buffer" API, with
friendlier alignment than `std140`. Out of reach unless the engine
bumps past the current 4.0 core shaders (`#version 400 core`) and
the macOS 4.1 ceiling.

macOS is hard-capped at OpenGL 4.1. That cap is Apple's
`OpenGL.framework`, not a missing loader library — installing a
newer GLFW/`zopengl` does not raise it. On this Mac the context
string is already `4.1 Metal - 90.5`: Apple's GL is a Metal
translation, still advertised as 4.1, so SSBO entry points stay
null. Texture buffers and UBOs are the portable 4.1 pair.

---

## Measured caps (this Mac)

Machine: MacBook Pro 14" (MacBookPro18,3), Apple M1 Pro, 16 GB
unified memory. Context created the same way as the games
(`4.1 core`, forward-compatible). Re-run with
`zig build gl_caps-run`.

| Query | This Mac | Spec minimum (GL 4.1) | What it means for 100-joint palettes |
|-------|----------|------------------------|--------------------------------------|
| `GL_VERSION` | `4.1 Metal - 90.5` | 4.1 | Confirms the Apple-on-Metal 4.1 ceiling |
| `MAX_VERTEX_UNIFORM_COMPONENTS` | **4096** | 1024 | 100 mat4s = 1600; current uniform path fits |
| `MAX_UNIFORM_BLOCK_SIZE` | **65536** | 16384 | **10** palettes per UBO (6400 B each) |
| `MAX_TEXTURE_BUFFER_SIZE` | **268435456** texels | 65536 | **671,088** palettes in one TBO |
| `MAX_TEXTURE_SIZE` | **16384** | 16384 | Pose atlas: 16384 instance rows if width = 400 |
| `MAX_VERTEX_TEXTURE_IMAGE_UNITS` | **16** | 16 | Vertex shader can `texelFetch` a palette texture |

The TBO number is the one that answers "can 4.1 do hundreds of
animated instances on this Mac?" Yes. 256 M texels × 16 bytes
(`RGBA32F`) is a 4 GiB theoretical buffer; 16 GB unified memory
and the CPU animator will give out long before the GL limit.

A 2D `RGBA32F` atlas of 400 × N is enough for 16,384 unique poses
in one texture. Hundreds is not even a large fraction of that.

So the local 4.1 implementation is not the thing that prevents a
crowd. The current 100-call uniform loop and one-draw-per-model
are.

---

## Vulkan / wgpu — does switching buy the headroom?

Raised 2026-08-16: convert
`/Users/john/Dev/Dev_Rust/small_wgpu_core` to Zig and leave
OpenGL, on the theory that Vulkan (or wgpu) is how you get past
4.1 and then instance hundreds of skinned models.

**On this Mac, "Vulkan" is still Metal.** There is no native
Vulkan ICD. wgpu defaults to the **Metal** backend. A Vulkan
path is MoltenVK (Vulkan → Metal). The GPU and the 16 GB
unified memory do not change. What changes is the API surface
and the size of the rewrite.

`small_wgpu_core` was already on that better surface, and it
used the same 100-matrix uniform array:

```wgsl
@group(1) @binding(2) var<uniform> bone_transforms: array<mat4x4<f32>, MAX_BONES>;
```

That is a UBO-shaped bind-group slot, not a storage buffer and
not a crowd path. wgpu's default uniform-buffer limit is 64 KiB
— the same 10-palette box this Mac reports for
`MAX_UNIFORM_BLOCK_SIZE`. The Rust project had not solved
"hundreds of independently posed instances" either; it had
solved "upload one palette without 100 API calls," which GL 4.1
can also do (`glUniformMatrix4fv` with a count, or a UBO).

Storage buffers (the SSBO equivalent) *are* a wgpu/Metal/Vulkan
feature GL 4.1 lacks. They are nicer to write than `texelFetch`
of four columns. They are not required for the instance counts
this GPU can already feed through a TBO.

### What a switch would cost

redfish already has the thing the Rust tree was aiming at:
native glTF, Cook-Torrance PBR, cubic-spline skinning, angrybot,
level_01, the allocator/`Context` rules. `small_wgpu_core` was
at "core + animation example, shadows in progress" when it
stopped. Porting it to Zig is a third engine, not a conversion
of the first. You would re-implement loading, materials, the
games, and the memory model on top of wgpu-native or a Vulkan
layer, then catch the current GL tree on features.

The difficulty of Vulkan is real and mostly front-loaded
(swapchains, sync, pipelines, descriptors). wgpu hides a lot of
that; that is why the Rust core got as far as it did. It does
not hide the fact that every system above the GPU context has
to be written again.

### When a switch *would* be the right move

- A deliberate backend change (Metal/Vulkan/DX12) for compute,
  bindless, multi-queue, or non-Mac targets that you care about
  more than the current GL games.
- Willingness to pause game work for months and treat
  redfish's GL tree as the reference, not the live engine.

It is not the move that unlocks "hundreds of animated models on
this Mac." That is a texture-buffer (or pose atlas) plus
instancing job on the engine you already have, and this
machine's 4.1 limits already allow it.

---

## Instancing vs. upload

`glDrawElementsInstanced` and `glVertexAttribDivisor` are in 3.3.
Per-instance `matModel` (four `vec4` attributes, divisor 1) is
easy. A 100-matrix palette is not: `MAX_VERTEX_ATTRIBS` is 16
`vec4`s.

So the split is:

- **Instance attributes:** model matrix, clip/time, palette offset.
- **Shared lookup table:** UBO (tiny), TBO, or 2D `RGBA32F`
  texture (the palette or the baked clip).

One mesh VAO, one texture/TBO bind, one instanced draw. That is
the 100s-of-instances shape.

---

## Two crowd problems, two texture answers

"Hundreds of instances at different points in their animation"
splits:

1. **Same clips, different times** (horde, wildlife, background
   NPCs). Bake sampled frames into a 2D `RGBA32F` texture once.
   Per instance: clip row-base + frame (or time). GPU fetch, maybe
   lerp two frames. CPU animator is not in the per-instance loop.
2. **Unique blends / IK / ragdoll / weighted clips per actor.**
   Each pose must be evaluated. Keep `Animator` on the CPU, write
   every palette into one TBO or one atlas row, draw instanced.
   The win is draw-call and uniform-call count, not animation
   math.

A third case — a handful of hero characters — does not need
textures at all. Path 1 or a per-character UBO is enough.

---

## Compaction (optional, later)

If the uniform / UBO budget ever hurts for a single palette:

- Skinning matrices are affine. The last row is `0 0 0 1`. Store
  three `vec4` columns (`mat3x4` in `std140` is 48 bytes) and
  rebuild the fourth in the shader. 25% less data. In `std140` a
  `mat4x3` does **not** shrink (each `vec3` column pads to 16
  bytes → still 64).
- Dual-quaternion skinning is two `vec4`s per joint. Half the
  bandwidth, different shader math, no scale unless you add a
  third vector.

Neither is required to escape the 100-call loop.

---

## Recommendation

Stay on `#version 400 core` / OpenGL 4.1.

1. Treat the current loop as an API-wrapper gap, not a spec limit.
   One `glUniformMatrix4fv` with `count = MAX_JOINTS` is legal, matches
   the existing shader, and matches `Animator.joint_matrices` layout.
2. Do not fear textures for this. The GLSL 4.10 lookup rules
   return raw floats from `RGBA32F` / `RGBA16F`. Use `texelFetch`.
   That is the technique from the video, and it is the one that
   scales to hundreds of instances.
3. Pick the texture layout from the crowd type: baked clip sheet
   when instances share clips; TBO / pose atlas when every pose is
   unique.
4. Keep UBOs in mind for hero characters and for getting 100 mat4s
   out of the default uniform block before a spec-minimum GPU (or
   a busier vertex shader) refuses to compile.
5. Leave SSBOs until there is a non-macOS / GL 4.3+ target.
6. Do not switch to Vulkan/wgpu to unlock instance counts on this
   Mac. The 4.1 TBO/atlas limits already cover hundreds of poses.
   A backend change is a separate, much larger bet.

---

## Pointers

- Current upload: `src/core/model.zig` `Model.draw` (the
  `jointMatrices[{d}]` loop).
- Wrapper: `src/core/shader.zig` `setMat4` (`count` hard-coded to 1).
- Storage: `src/core/animator.zig` `joint_matrices: [MAX_JOINTS]Mat4`,
  `src/math/mat4.zig` (`extern struct`, column-major).
- Shader declaration: `examples/animation_example/player_shader.vert`
  line 15, and the copies in `examples/demo_app/shaders/`,
  `games/level_01/shaders/`, `games/angrybot/shaders/`.
- GLSL 4.10: uniforms / uniform blocks; texture lookup functions
  (`texelFetch`, `samplerBuffer`).
- Caps probe: `examples/gl_caps/main.zig`, `zig build gl_caps-run`.
- OpenGL 4.1 API: `UniformMatrix4fv` count; `MAX_VERTEX_UNIFORM_COMPONENTS`;
  `MAX_UNIFORM_BLOCK_SIZE`; `MAX_TEXTURE_BUFFER_SIZE`; Table of sized
  internal formats (`RGBA32F` vs unsigned-normalized `RGBA8`).
