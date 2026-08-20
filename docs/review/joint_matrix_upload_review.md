# Joint-Matrix Upload Review — 2026-08-15

Two questions.

First: `Model.draw` in `src/core/model.zig` calls `glUniformMatrix4fv`
once per array slot, roughly 100 calls per skinned model. Under GLSL
4.10 and OpenGL 4.0–4.1, is that the only legal way to fill
`uniform mat4 jointMatrices[MAX_JOINTS]`?

Second: if hundreds of instances of the same mesh each need a different
pose, is a texture the right next step? And does reading floats from a
texture force normalization?

Prompted by reading the GLSL 4.10 Specification end to end, and by an
animation-texture technique shown in a video.

**Status (revised 2026-08-16).** Path 1 has landed. Commit `4147f1e`
added `Shader.setMat4Array`, and `Model.draw` now uploads the whole
palette in one `glProgramUniformMatrix4fv`. Sections marked *done* are
kept for the reasoning, not as pending work. This revision also adds the
engine-level blocker the original note missed: GL limits were never what
stopped this engine from drawing a crowd.

---

## TL;DR

The 100-call loop is a **wrapper choice**, not a language or API
requirement. The GLSL spec covers how a shader *declares and indexes* a
uniform array. The **OpenGL API** spec covers how the host writes it,
and that API has taken a count since OpenGL 2.0:

```
glUniformMatrix4fv(location_of_jointMatrices, 100, GL_FALSE, first_float);
```

One call for the whole palette. `Mat4` is already an `extern struct` of
16 tightly packed `f32`s, and `Animator.joint_matrices` is a contiguous
`[MAX_JOINTS]Mat4`. The bytes are already in the layout that call wants.

That fix does **not** give you hundreds of independently posed instances
in one draw. Default-block uniforms are per-program state, so every
instance still needs its own upload and draw, or a different binding.
For that scale, still on GL 4.0/4.1, the options are:

| Path | GL / GLSL | Good for | Blocker at 100s of instances |
|------|-----------|----------|------------------------------|
| One `glUniformMatrix4fv` with `count = N` | 2.0 / 1.10 | one (or a few) characters | still one upload+draw per unique pose |
| Uniform buffer (`std140` block) | 3.1 / 1.40 | one palette, cheap rebind | `MAX_UNIFORM_BLOCK_SIZE` is only guaranteed 16 KiB (~256 mat4s) |
| Texture buffer (`samplerBuffer` + `RGBA32F`) | 3.1 / 1.40 | many unique poses, one instanced draw | none at hundreds; this is the GL 4.1 tool |
| 2D float texture (`texelFetch` + `RGBA32F`) | 3.0 / 1.30 | baked clips *or* a pose atlas | same; this is the video technique |
| SSBO | **4.3 / 4.30** | huge structured arrays | **not in 4.1** |

**Textures do not have to normalize.** Normalization comes from the
*internal format*, not from reading a texture. `GL_RGBA8` and `GL_RGBA`
normalize to `[0,1]`. `GL_RGBA32F` and `GL_RGBA16F` return the stored
floats unchanged. `texelFetch` then reads them at integer texel
coordinates with no filtering. That is why the video technique works for
skinning matrices.

The order to work in:

0. **Done (`4147f1e`):** one `glProgramUniformMatrix4fv` for
   `jointMatrices` with `count = MAX_JOINTS`. One cached location.
   The `bufPrintZ("jointMatrices[{d}]", i)` loop is gone.
1. **The actual blocker is the engine, not GL.** `Model` owns both the
   GPU buffers *and* the `Animator`, so instances cannot have
   independent poses without duplicating VAOs and VBOs. Split
   per-instance state out of `Model` before any texture work. See
   [The engine blocker](#the-engine-blocker-model-owns-too-much) for the
   problem and
   [Shaping the split](#shaping-the-split-pose-source-and-instancing)
   for the pose-source union and instancing design.
2. **Two free wins, available today.** `Model.draw` uploads a joint
   palette even for unskinned models, which is 6400 bytes of identity
   matrices per prop per frame. A one-line `skin_index` guard fixes it.
   And `EnemySystem.drawEnemies` re-uploads an identical palette and
   re-walks the node tree once per enemy; hoist both out of the loop.
   See [Redundant per-instance upload](#redundant-per-instance-upload).
3. **Hundreds of instances:** one `RGBA32F` texture buffer or 2D texture
   holding every instance's palette, or every baked clip frame, drawn
   with one `glDrawElementsInstanced`. Instance id selects the row,
   joint id selects the columns. This costs vertex-stage bandwidth; see
   [What the texture path costs](#what-the-texture-path-costs).

Most write-ups put a `std140` UBO between 0 and 3. On this machine it is
not worth the complexity. See
[Path 2](#path-2--uniform-buffer-gl-31-already-in-41).

**Measure before building any of this.** The caps table below shows GL
is not the constraint. The CPU animator probably is, and the texture
paths do not help with animation math. See
[Measure first](#measure-first).

---

## The engine blocker: `Model` owns too much

Everything below about TBOs and pose atlases assumes an instance id
picks a row. This tree has no instance id, because it has no instance.
From `src/core/model.zig`:

```zig
pub const Model = struct {
    meshes: *ManagedArrayList(*Mesh),   // GPU buffers  — shareable
    animator: *Animator,                // pose state   — per-instance
    gltf_asset: *GltfAsset,             // source data  — shareable
```

Three different lifetimes in one struct. You can see the result in
`games/angrybot/enemy.zig`. `EnemySystem` holds a single
`enemy_model: *Model`, and `drawEnemies` loops over `state.enemies`,
setting a per-enemy `model` transform and calling
`self.enemy_model.draw(shader)` each time. GPU buffers are shared, which
is good. But so is the one `Animator`, so **every enemy is locked to the
same pose at the same phase**. The crowd already exists. It is just
frozen in lockstep.

Today the engine offers exactly two shapes, and neither is a crowd:

| Shape | GPU buffers | Poses | Cost |
|-------|-------------|-------|------|
| One `Model`, N draws (angrybot enemies) | shared | **one, shared** | cheap, but every instance identical |
| N `Model`s, N draws | **duplicated per instance** | independent | N× VAO/VBO/EBO for identical geometry |

No GL feature fixes that. Separate per-instance state from shared
resources instead:

```zig
// shared, loaded once
Model { meshes, gltf_asset }

// per instance
ModelInstance { model: *Model, animator: *Animator, transform: Mat4,
                clip: u32, time: f32 }
```

`Animator` already holds only per-instance data: `active_animations`,
`weight_animations`, `joint_matrices`, and node transforms. So the split
is mostly mechanical. Move the field, then thread an explicit animator
through `Model.draw` and `drawNodes` instead of reading `self.animator`.
Do this first. TBO rows, atlas rows, and `gl_InstanceID` only become
expressible once it exists.

---

## Shaping the split: pose source and instancing

Design notes on *how* to make that split, added 2026-08-18.

### Inject the pose source, don't construct it

`GltfAsset.buildModel` currently does skin discovery, then calls
`Animator.init(self.context, self, skin_index)` and hands back a `Model`
with the animator already baked in. That leaves the asset loader
deciding animation policy, which is not its job. Pass the pose source in
instead, either as a parameter or as a setting on `GltfAsset` next to
`setNormalGenerationMode`. That change stands on its own, independent of
everything else here.

### `Animator` is two responsibilities, and only one of them varies

Before adding variants, look at what `Model.draw` actually reads:

```zig
if (!self.animator.nodes[node_index].is_visible) return;                  // model.zig:108
const transform = self.animator.nodes[node_index].calculated_transform.?; // model.zig:111
```

That is the glTF node hierarchy, and **every** model needs it, skinned
or not. Today a static prop still gets a full `Animator` built purely to
hold its node transforms.

| Responsibility | Who needs it | Varies by strategy? |
|----------------|--------------|---------------------|
| Node hierarchy state (`calculated_transform`, `is_visible`) | every model | no |
| Skinning palette production | skinned models only | **yes — this is the strategy** |

So a "null" pose source cannot be null until the hierarchy state moves
out. Pull it into something `Model` always owns. Only then can the
palette side be swapped for a genuinely empty variant. This fits the
`ModelInstance` split above: node transforms are still per-instance
state, they are just not *animation* state.

### The strategy is a tagged union with a `bind` method

```zig
const PoseSource = union(enum) {
    active: *Animator,   // live CPU evaluation — blending, cubic spline, IK
    baked:  BakedClip,   // clip row + time; shader texelFetches the palette
    static,              // no skinning at all

    pub fn bind(self: PoseSource, shader: *const Shader) void { ... }
};
```

Two decisions behind that shape:

**Tagged union, not a vtable.** You get exhaustive compile-time dispatch
and no indirection, and it matches the union-based interpolation
dispatch this codebase already uses for cubic-spline selection.

**The interface is "bind what you need", not "return a palette."** `baked` is
not a drop-in replacement for `active`. It does not produce
`joint_matrices` on the CPU at all. It uploads a clip row and a time and
lets the vertex shader fetch the matrices, which also means a different
shader. An interface defined as "give me `[MAX_JOINTS]Mat4`" cannot
express that. One defined as "set up the uniforms for this draw" can.

**`static` saves real work every frame.** `Model.draw` uploads the
palette unconditionally:

```zig
shader.setMat4Array(constants.Uniforms.Joint_Matrices, &self.animator.joint_matrices);
```

There is no skin check. Every unskinned model sends **6400 bytes of
identity matrices to the GPU on every draw of every frame**, plus the
`glProgramUniformMatrix4fv` call itself. At 100 static props and 60 fps
that is about 38 MB/s and 6000 uniform calls per second, all of it
wasted. On a GL-to-Metal translation layer it costs more than the byte
count suggests, because the translation has to version constant storage
per draw.

You might argue this is harmless since the shaders already branch on
`hasSkin`. That branch stops the *shader* doing wasted work. It does
nothing about the upload, which happens either way.

`static` also avoids building an `Animator` for props at all, so it
saves init time and resident memory too. But the per-frame upload is the
bigger and more immediate win.

**This one does not need the refactor.** `Animator.skin_index` is
already `?u32`, and null whenever the glTF declares no skins, so the
guard works today:

```zig
if (self.animator.skin_index != null) {
    shader.setMat4Array(constants.Uniforms.Joint_Matrices, &self.animator.joint_matrices);
}
```

The `static` union arm makes it structural instead of a runtime branch,
which is where you want to end up. The guard gets most of the benefit
now.

### Instancing on `Model`

`num_instances` belongs as a **parameter to `draw`**. As a **field on
`Model`** it works against the split above, since instance count is
per-draw-call state and `Model` is becoming the shared resource. Do not
put it back in.

Swapping in `glDrawElementsInstanced` is the easy part. The real work is
that the per-instance model matrix must stop being a uniform. Today the
caller sets it: `drawEnemies` calls `shader.setMat4("model", …)` per
enemy. A uniform is constant for the whole draw call by definition, so
it cannot differ between instance 0 and instance 1. There are exactly
two ways to supply per-instance data, and the engine should pick one.

#### Decision: index by `gl_InstanceID` (route b)

**Chosen 2026-08-18.** Shaders read instance data by indexing a buffer
with `gl_InstanceID`, rather than having GL feed each instance its own
attribute values.

| | (a) Divisor attributes | **(b) `gl_InstanceID` indexing** |
|---|---|---|
| Mechanism | `glVertexAttribDivisor(loc, 1)` | `texelFetch(tbo, gl_InstanceID * stride + …)` |
| Setup | per-VAO attribute wiring, on **every** `MeshPrimitive` | bind one buffer per shader; VAOs untouched |
| Reachable by a caller | no — the VAO is private to `MeshPrimitive` | yes — bind a buffer, set a base-offset uniform |
| Per-instance payload | ≤ `MAX_VERTEX_ATTRIBS` (16 `vec4`s) | unbounded |
| Instance count | unbounded | bounded by the backing store (see below) |
| Per-draw instance offset | needs `glDrawElementsInstancedBaseInstance` — **GL 4.2, unavailable** | a base-offset uniform |
| Per-vertex cost | fixed-function fetch (essentially free) | explicit `texelFetch`es |

Route (b) wins structurally: you bind the instance buffer once at the
shader level, no matter how many VAOs a model contains. Route (a) would
need the instance attribute wired into every primitive's VAO, and a
caller outside `Model` has no handle to those VAOs at all. Route (b)
also composes with the pose-source work, since one buffer can carry both
model matrices and joint palettes indexed by `gl_InstanceID`. Instancing
and skinning then land on one mechanism.

What the decision implies, all applied in `61e1d74` and `7abe59e`:

- `Shape.drawInstanced`, the `transforms_vbo` buffer, and its four
  divisor attribute bindings are gone from `src/core/shapes/shape.zig`.
  One convention, engine-wide.
- `constants.VertexAttr.INSTANCE_MATRIX` is deleted, rather than left as
  a reserved slot for a route not taken.
- The `is_instanced` flag existed only to gate that block, so it went
  too, from `ShapeBuilder`, `initGLBuffers`, `CubeConfig`, and every call
  site.
- `examples/bullets/projectiles/bullet_system.zig` still uses divisor
  attributes for its own bullet quads. It is a self-contained example,
  not core, so it can migrate later or stay as a counter-example. It
  should not be cited as the pattern to copy.

#### Per-draw instance offsets need GL 4.2

The strongest argument against route (a) is not bandwidth. It is a
capability GL 4.1 does not have.

`Model.draw` walks the node tree and issues one draw per mesh node. With
a single shared instance buffer, each of those draws needs to start
reading at a different point in that buffer. The API for that is
`glDrawElementsInstancedBaseInstance`, from `ARB_base_instance`, which
is **OpenGL 4.2**. That puts it above the macOS ceiling, like DSA and
SSBOs.

Without it, route (a) leaves two workarounds at 4.1:

- Re-call `glVertexAttribPointer` with a new offset before each draw.
  That rewrites VAO state every frame, putting the per-primitive work
  back in the hot path, which is what the VAO was meant to lift out of
  it.
- Keep one instance buffer per batch, which multiplies buffers instead
  of offsets.

Route (b) has no equivalent problem. The base offset is an integer
uniform, and the shader indexes `gl_InstanceID + baseOffset`. No API
support needed.

#### VAO and VBO are independent objects

Worth stating plainly, because assuming they are tightly coupled gives
you the wrong cost model for route (a).

A VAO is a container of *configuration*, nothing more. Per attribute
slot it holds: the enabled flag, the format (size, type, normalized,
stride, offset), the divisor, and **the buffer object captured at
`glVertexAttribPointer` time**. It also holds one per-VAO
`GL_ELEMENT_ARRAY_BUFFER` binding. It does not hold the current program,
uniform values, texture bindings, the `GL_ARRAY_BUFFER` binding itself,
or any depth, blend, or cull state.

Two consequences matter here:

**One VBO can back many VAOs.** `glVertexAttribPointer` captures
whatever is bound to `GL_ARRAY_BUFFER` *at that moment* into that VAO's
slot. Nothing stops N VAOs from capturing the same buffer object. So
route (a) would not have meant N uploads per frame:

```zig
// setup, once per primitive — the same buffer every time
gl.bindVertexArray(p.vao);
gl.bindBuffer(gl.ARRAY_BUFFER, instance_vbo);
// vertexAttribPointer + vertexAttribDivisor …

// per frame — once, not once per primitive
gl.bindBuffer(gl.ARRAY_BUFFER, instance_vbo);
gl.bufferSubData(gl.ARRAY_BUFFER, 0, size, data);
```

Every VAO references the same buffer object, not a copy. **Per-frame
upload cost is identical between the two routes.** The real differences
are setup complexity, whether a caller can reach it, payload size, and
the base-instance gap above. Not bandwidth.

**Attribute bindings do not rebind like textures.** A texture binding is
context state, read at draw time, so `glBindTexture` before a draw
redirects the sampler. An attribute's buffer reference lives *inside the
VAO*. Binding a different VBO to `GL_ARRAY_BUFFER` before a draw does
nothing, because `glDrawElements` never reads it. Re-pointing an
attribute means binding the VAO, binding the new buffer, and calling
`glVertexAttribPointer` again, which rewrites VAO state.

So the 4.1 way to switch data sources cheaply is **pre-built VAO
variants**. VAOs are cheap to bind, though not free to create, so build
them up front and never per frame. Make several, each capturing a
different buffer combination, and swap with one `glBindVertexArray`.

GL 4.3's separate attribute format is the API that would make buffer
swapping work the way textures do. `glVertexAttribFormat` declares the
layout once, and `glBindVertexBuffer` re-points a binding slot without
re-specifying anything. Out of reach here, same ceiling as everything
else in [Path 4](#path-4--not-available-on-41).

One place this pattern could pay off outside instancing: angrybot's
shadow pass renders depth only, so it needs position, plus joints and
weights when skinned, and nothing else. Yet the VAO has all seven
attributes enabled. A second depth-only VAO per primitive would drop the
rest. Measure before building it. Modern drivers often already skip
fetches for attributes the linked program does not consume, and it
doubles the VAO count per primitive.

#### Does route (b) hit a size cap sooner?

Only if you back it with a **uniform buffer**. The cap belongs to the
storage, not to the indexing:

| Backing store | Cap on this Mac | Instances at 64 B each (one `mat4`) |
|---------------|-----------------|-------------------------------------|
| UBO array | `MAX_UNIFORM_BLOCK_SIZE` = 65,536 B | **1,024** — a real ceiling |
| Texture buffer (`samplerBuffer`, `RGBA32F`) | `MAX_TEXTURE_BUFFER_SIZE` = 268,435,456 texels ≈ 4 GiB | ~67,000,000 — no practical limit |
| 2D `RGBA32F` texture | 16,384 × 16,384 texels ≈ 4 GiB | same order |

Back it with a **TBO**, not a UBO, and route (b) has *more* headroom
than route (a), not less: unbounded per-instance payload, and an
instance count that memory exhausts long before GL does. A UBO would put
the 65 KiB box back for no benefit; see
[Path 2](#path-2--uniform-buffer-gl-31-already-in-41).

What route (b) does cost is vertex-stage bandwidth. The model matrix
becomes four more `texelFetch`es per vertex on top of the palette
fetches, where route (a) would have had the hardware fetch it through
the fixed-function attribute path. That is the same trade priced in
[What the texture path costs](#what-the-texture-path-costs), now applied
to the model matrix as well. Measure it at your target instance count.
It is not worth splitting into two conventions in advance.

One clarification, since the setup saving is easy to overstate: route
(b) still creates and uploads a buffer. What goes away is the *per-VAO
attribute wiring*, meaning the `vertexAttribPointer` and
`vertexAttribDivisor` calls route (a) needs on every `MeshPrimitive`.
For a model with many primitives that is most of the setup, but the
buffer itself remains.

#### What stays a uniform

`nodeTransform` stays a uniform. It is per-node and shared across all
instances, so `drawNodes` still walks the tree and issues one *instanced*
draw per mesh node. The node walk and instancing compose without
conflict.

### Order to build it

1. Split node-hierarchy state out of `Animator`.
2. Inject the pose source at `buildModel` instead of constructing it
   there. Start with a `union(enum)` of `active` and `static`.
3. `instance_count` parameter on `draw` (landed), plus a `gl_InstanceID`
   -indexed TBO for model matrices. Usable immediately, at one shared
   pose per batch. Delete `Shape.drawInstanced` and
   `VertexAttr.INSTANCE_MATRIX` as part of this step so only one
   instancing convention survives.
4. Add `baked` as a third arm once there is a bake pipeline and a shader
   to match.

Steps 1–3 are mechanical, and none of them requires deciding anything
about textures. Step 3 alone turns angrybot's N enemy draws into one
instanced draw, still in lockstep. That is
[pose pool](#1-pose-pool--n-instances-k-distinct-poses-k--n) with K = 1,
and the natural place to raise K afterwards.

---

## Redundant per-instance upload

Two uploads that should not be happening. Both are fixable now,
independent of the split above.

### a. Unskinned models still upload a joint palette

`Model.draw` calls `setMat4Array` with no skin check, so every static
prop pushes 6400 bytes of identity matrices per frame. `skin_index` is
already `?u32` and null for unskinned glTFs, so the fix is a one-line
guard. Details and cost in
[What `static` is actually worth](#the-strategy-is-a-tagged-union-with-a-bind-method).

### b. Shared-animator instances upload identical data N times

`Model.draw` uploads the full 100-matrix palette via `setMat4Array`,
6400 bytes, and then `drawNodes` walks the whole node tree issuing a
`setMat4(Node_Transform, …)` per node. `drawEnemies` calls it once per
enemy. Because the animator is shared, **every one of those uploads is
byte-identical across enemies**.

For N enemies that is N × (one `glUseProgram`, a 6400-byte palette
upload, and a full node-tree walk with a matrix upload per node) to send
the same data N times. Hoist the palette and the node walk out of the
per-enemy loop, leaving only `model` and `aimRot` inside. It is a small,
local change with no architectural commitment.

Best return for the effort of anything in this note.

---

## Measure first

The caps table below shows GL is not the limit on this machine: 671k
palettes fit in a TBO, and 16,384 rows fit in a 2D atlas. Before
building a texture pipeline, find out which of these is actually the
wall at your target instance count:

- **Draw calls** — one per instance today. Fixed by instancing.
- **Uniform uploads** — see [Redundant per-instance upload](#redundant-per-instance-upload).
  Much of the current cost is duplicate data, not necessary data.
- **CPU animation** — `Animator` runs per instance per frame: keyframe
  interpolation, a node-tree walk, and one `mulMat4` per joint against
  the inverse bind matrix. **No texture path helps here** unless you
  bake, which removes the animator from the loop entirely.
- **Vertex processing** — skinning math per vertex, plus texel fetches
  if you move the palette into a texture.

The first three call for different fixes. Guess wrong and you build a
TBO pipeline to solve a problem that was CPU-side.

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
4.0 / 4.1 API specification, and in the `glUniform` reference page. Read
only GLSL and "one name per array element" looks like the whole story,
because that is how the shader *mentions* elements. The API has always
treated the array as one uniform whose first-element location accepts a
count.

Two traps follow from that split:

- Sequential elements do **not** have sequential locations. You cannot
  take `loc(jointMatrices[0])` and add `i`. Either query each name, or
  pass `count > 1` at the first element's location. The old loop did the
  first; the API prefers the second.
  (The guarantee people remember is real, but only for *explicit*
  locations: `layout(location = 2) uniform mat4 mats[10]` assigns the
  half-open range [2, 12). That is `ARB_explicit_uniform_location` /
  GL 4.3, so it is unavailable under the macOS 4.1 ceiling. With queried
  locations, `loc("a[0]") + 1` may name an entirely different uniform.)
- `glGetUniformLocation(program, "jointMatrices")` and
  `"jointMatrices[0]"` are both defined to return the first element.
  That is the location the count-form call uses.

---

## Cost in this tree — before and after `4147f1e`

**Before.** `Model.draw` (`src/core/model.zig`) for every skinned draw:

1. Formatted `"jointMatrices[0]"` … `"jointMatrices[99]"` with
   `bufPrintZ`.
2. Looked each name up in `Shader.locations`, and on first use called
   `glGetUniformLocation` 100 times, storing 100 duped string keys per
   shader.
3. `setMat4` → `useShader()` + `glUniformMatrix4fv(..., count = 1, ...)`.
4. Copied each `Mat4` onto the stack (`const joint_transform = ...`)
   before taking its address.

**After.** One cached location, one call:

```zig
shader.setMat4Array(constants.Uniforms.Joint_Matrices, &self.animator.joint_matrices);
```

`Shader.setMat4Array` takes `[]const Mat4` and derives `count` from
`.len`, so the count and the pointer cannot disagree.

`Animator.joint_matrices` is `[MAX_JOINTS]Mat4`, and `Mat4` is
column-major, 64 bytes, no padding. That is exactly the layout
`glProgramUniformMatrix4fv` with `transpose = GL_FALSE` expects. The
contiguous upload was a pointer and a count, never a packing problem.

Note what this did *not* fix. The palette is still uploaded once per
`Model.draw`, so N instances sharing one animator still pay N uploads of
identical bytes. See
[Redundant per-instance upload](#redundant-per-instance-upload).

---

## Path 1 — same declaration, one API call — **done (`4147f1e`)**

OpenGL 4.1 `glUniform` / `UniformMatrix4fv`:

> For the matrix commands, `count` is the number of matrices to
> modify. This should be 1 if the targeted uniform is not an array of
> matrices, and 1 or more if it is.

As shipped, in `Shader.setMat4Array`:

```zig
gl.programUniformMatrix4fv(
    self.id,
    location,
    @intCast(mat_array.len),
    gl.FALSE,
    @ptrCast(mat_array.ptr),
);
```

The shader is unchanged: `uniform mat4 jointMatrices[MAX_JOINTS];`.

This was the right first move, and it changed nothing about instancing.
Default-block uniforms are program state, so instance B overwrites
instance A's palette. Hundreds of unique poses still mean hundreds of
uploads and hundreds of draws.

### Uniform-component budget

The OpenGL 4.0/4.1 minimum for `MAX_VERTEX_UNIFORM_COMPONENTS` is
**1024**. A `mat4` is 16 components, so `jointMatrices[100]` is
**1600** — before `matProjection`, `matView`, `matModel`,
`nodeTransform`, and `matLightSpace`. Desktop NVIDIA, AMD, and Intel
parts, and macOS GL 4.1, typically report 4096 or more, which is why 100
joints compiles here. It would not port to a vertex stage at the spec
minimum.

This machine was measured 2026-08-16 with `zig build gl_caps-run`:
**4096** components, so 100 mat4s fit with 2496 left. The spec-minimum
worry is not the local constraint. See
[Measured caps](#measured-caps-this-mac) for the rest.

The original note used this budget to argue for a UBO even for a single
character. With 2496 components spare on the only GPU this engine
targets, that argument does not hold. See the verdict at the end of
Path 2.

---

## Path 2 — uniform buffer (GL 3.1, already in 4.1)

GLSL 4.10 uniform blocks:

```glsl
#version 400 core
layout(std140) uniform JointBlock {
    mat4 jointMatrices[MAX_JOINTS];
};
```

Under `std140`, a column-major `mat4` is four `vec4` columns, each
16-byte aligned, so one matrix is 64 bytes and an array of them packs
tightly. That matches `Mat4` and `[MAX_JOINTS]Mat4`. One
`glBufferSubData`, or a persistently mapped buffer, replaces the uniform
calls. Bind with `glBindBufferBase` or `glBindBufferRange`.

The `MAX_UNIFORM_BLOCK_SIZE` minimum is **16384 bytes**, or 256 mat4s.
One character at 100 × 64 = 6400 bytes fits, and so do a few packed
palettes. Hundreds of palettes do **not** fit in one block on min-spec,
and often not on desktop either, since 64 KiB is a common cap, giving
about 10 palettes of 100 joints.

So a UBO is:

- The right upgrade for "several characters, one draw each."
- A way to stop eating the default-block component budget.
- Not the crowd or instancing solution, unless you batch by how many
  palettes fit in one bind and pass a per-instance palette offset. That
  is still a small multiple, not hundreds.

**Verdict for this engine: skip it.** A UBO buys two things here.
Component-budget relief, which is not needed with 2496 components spare
on a tree that only runs on Apple GL 4.1. And cheaper rebinds for a
handful of characters, which Path 1 already made cheap at one call and
6400 bytes. In exchange it adds `std140` layout rules, buffer lifetime,
and a binding-point allocation scheme. Go straight from Path 1 to
Path 3 when the crowd arrives. Revisit only if a non-Apple,
spec-minimum target appears.

---

## Path 3 — textures, and the normalization question

The video is almost certainly using this technique, and it is valid in
GLSL 4.10. Normalization is the usual objection, and it is a format
mix-up.

### What actually normalizes

| Internal format | What `texelFetch` / `texture` return |
|-----------------|--------------------------------------|
| `GL_RGBA`, `GL_RGBA8`, `GL_RGB8` | unsigned-normalized `[0, 1]` |
| `GL_RGBA8_SNORM` | signed-normalized `[-1, 1]` |
| `GL_RGBA16F`, `GL_RGBA32F` | the stored floats, unchanged |
| `GL_RGBA32I` / `GL_RGBA32UI` | integers (`isampler*` / `usampler*`) |

The GLSL 4.10 texture-lookup chapter says floating-point textures return
their values as-is. Unsigned normalized formats are the ones mapped to
`[0, 1]`. Skinning matrices want **`GL_RGBA32F`**, or `GL_RGBA16F` if
you accept 3–4 decimal digits, which is usually too thin once
translation is in the matrix.

`texture()` also applies wrap and filter, and takes normalized `[0,1]`
*coordinates*. For matrices use **`texelFetch`** instead: integer texel
coordinates, no filter, exact texel. Set `GL_TEXTURE_MIN_FILTER` and
`MAG_FILTER` to `GL_NEAREST` in case anything ever samples it with
`texture()`.

sRGB formats also convert. Do not store palettes in sRGB.

### 3a. Texture buffer (`samplerBuffer`)

GL 3.1. A 1D buffer of texels addressed by integer index. A natural fit
for an array of vec4 columns.

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

On the host: `glTexBuffer(GL_TEXTURE_BUFFER, GL_RGBA32F, vbo)`. Upload
with `glBufferSubData` on that buffer, the same as any other VBO.

The `MAX_TEXTURE_BUFFER_SIZE` minimum is **65536 texels**. Each joint is
4 texels, one per column, so 100 joints is 400 texels. Min-spec holds
`65536 / 400 ≈ 163` full palettes, and real drivers are orders of
magnitude larger. Hundreds of unique poses in one buffer is comfortable.

This is the GL 4.1 answer to "many instances, each with its own
evaluated pose, one instanced draw."

### 3b. 2D float texture (the usual video)

Two layouts, both `GL_RGBA32F`, both read with `texelFetch(..., lod = 0)`:

**Pose atlas (upload every frame).**
Width = `MAX_JOINTS * 4` texels, since one matrix is four RGBA pixels.
Height = instance count. Row `gl_InstanceID` is that instance's palette.
The CPU still runs `Animator` per instance; the GPU just reads the
results without a uniform round-trip per draw.

**Baked clip sheet (upload once).**
Width = joints × 4. Height = sampled frames of a clip, or of stacked
clips. Each instance carries only a clip id and a time, or two frame
indices plus a lerp. The CPU animator goes away for simple playback.
This is what most "we put animation in a texture" talks mean, and it is
the right path when hundreds of instances share a few clips and differ
only by phase.

The bake is an offline or load-time pass that runs the existing
`Animator` once per clip:

1. Step the clip at a fixed rate, say 30 Hz, from 0 to `clip.duration`.
2. At each step, run the normal `updateAnimation` and copy the resulting
   `joint_matrices` into one **row** of the texture.
3. Row `f` of clip `c` then holds the entire 100-joint palette at frame
   `f`. Width stays `joints × 4` texels. Height grows by
   `ceil(duration × 30)` rows per clip. Clips stack vertically, and each
   instance carries the row offset where its clip begins.

At draw time the shader converts the instance's playback time to a
fractional frame, fetches the two bracketing rows, and blends:

```glsl
float f      = instanceTime * bakedFps;      // fractional frame
int   f0     = int(floor(f));
int   f1     = min(f0 + 1, clipLastFrame);
float t      = fract(f);
mat4  m      = mix(fetchJoint(clipRow + f0, joint),
                   fetchJoint(clipRow + f1, joint), t);
```

The fixed bake rate is the tradeoff. The clip is no longer continuous,
it is sampled, and the shader reconstructs between samples. Two things
to know before committing:

- **Lerping matrices is an approximation.** A linear blend of two
  rotation matrices is not a rotation; it shears and shrinks slightly
  mid-blend. At 30 Hz the per-frame rotation delta is small enough that
  the artifact is invisible on a background character. Do not ship it on
  a hero model in close-up. Baking TRS instead of matrices (translation
  `vec3`, rotation `quat`, scale `vec3`) and rebuilding in the shader
  gives correct slerp, at the cost of more vertex math and a different
  texture layout.
- **Bake rate versus memory is cheap.** One row is 100 joints × 4 texels
  × 16 bytes = **6400 bytes**. A 2-second clip at 30 Hz is 60 rows, about
  **384 KB**. Ten clips is about **3.8 MB**. Doubling to 60 Hz to halve
  the interpolation error still lands under 8 MB. Memory is not a reason
  to keep the bake rate low.

Do not rely on `GL_LINEAR` to do the blend for you. Sampling across a
matrix stored as four adjacent pixels filters the four columns
independently and produces a garbage matrix. Set `GL_NEAREST` and blend
explicitly, as above.

### Bake node transforms too, not just the joint palette

A full bake needs more than `joint_matrices`. Joints are *derived*:
`animator.zig:529` computes them as
`node_matrix.mulMat4(&joint.inverse_bind_matrix)`. What animation
actually drives is `nodes[i].calculated_transform`, and for an
**unskinned** mesh that transform is the entire animation. Baking only
the palette would silently drop every rigid-body animation: a rotating
propeller, a sliding door, a mechanical assembly.

The shader already treats these as mutually exclusive. From
`examples/demo_app/shaders/pbr.vert`:

```glsl
if (hasSkin) {
    // jointMatrices only — nodeTransform is never applied
    vec4 localPosition = jointMatrices[inJointIds[i]] * vec4(inPosition, 1.0);
    ...
} else {
    totalPosition = nodeTransform * vec4(inPosition, 1.0);
}
```

So `hasSkin` picks which region of the baked row to read, and shader
*semantics* do not change at all. Only the source of the matrices does.
This also matches the glTF spec, which requires a skinned mesh node's
own transform to be ignored, since placement is already carried by the
joint hierarchy and the inverse bind matrices.

**`hasSkin` is per-primitive, not per-model.** It is set on each
`MeshPrimitive` from attribute presence (`mesh.zig:185`) and uploaded per
primitive at draw (`mesh.zig:267`). So one model can take both branches
in the same frame, such as a character with a skinned body and a rigid
prop mesh. The flag is a *runtime region selector*, not a bake-time
either/or. A mixed model bakes both regions.

**The uniform becomes an index.** `drawNodes` already knows the node
index, since it is the loop variable, so `setMat4(Node_Transform, …)`
becomes a `setInt` at the same call site:

```glsl
uniform int nodeIndex;   // replaces uniform mat4 nodeTransform
```

The joint side needs no index uniform, since `inJointIds[i]` already
supplies it.

**`is_visible` does not get baked.** It is written only by the explicit
setters in `model.zig:220-256`, and the animator never touches it. It is
engine state rather than animation state, so it stays a CPU-side check in
`drawNodes`.

#### Layout: store every node, or compact and remap?

Storing transforms only for mesh-bearing nodes is tempting. `drawNodes`
reads `calculated_transform` only when `node.mesh != null`, and joint
nodes are already folded into the palette. But then the glTF node index
no longer addresses the texture directly, and you need a remap.

Per frame, for a rigged character with about 100 nodes of which about 8
carry meshes:

| Layout | Joints | Transforms | Row total | 10 clips @ 30 Hz, 2 s |
|--------|--------|-----------|-----------|------------------------|
| All nodes | 6,400 B | 6,400 B | 12,800 B | ~7.7 MB |
| Mesh nodes only | 6,400 B | 512 B | 6,912 B | ~4.1 MB |

Compaction nearly halves the bake, but both numbers are trivial against
16 GB of unified memory and a 4 GiB TBO ceiling. So **store every node**.
The texture layout then mirrors the glTF node array exactly, which is
worth more in debugging than 3 MB is in memory.

Two notes for whenever that stops being true:

- The remap is cheaper than it looks. `nodeIndex` is a uniform set per
  draw from the CPU, so the indirection lives entirely on the host:
  `drawNodes` passes `node_row[node_index]` instead of the raw index. No
  shader-side lookup table, no per-frame cost, one static array built at
  bake time.
- The waste is worst where it matters most. A heavily rigged character
  has the most nodes *and* the fewest that need a stored transform, so
  the all-nodes region is nearly all padding for exactly the assets a
  crowd is made of.

### Fidelity tiers — hero versus horde

This does not have to be all-or-nothing. Animation supports an LOD
ladder the same way geometry does:

| Tier | Path | Pose source | Cost |
|------|------|-------------|------|
| Hero / player | Path 1 uniform palette | live `Animator`, full blending, IK | one upload + one draw per character |
| Mid — a few named NPCs | live `Animator` → TBO row | live, unique | one upload per actor, one instanced draw |
| Horde / background | baked clip sheet | sampled + lerped | zero animation cost per instance |

The player keeps `updateWeightedAnimations`, cubic-spline interpolation,
and whatever IK or ragdoll arrives later. None of that survives a bake.
The horde gets sampled clips with linear blending, where nobody is
looking closely enough to notice an approximated rotation. Both paths
share the same mesh and the same shader if the shader branches on a
uniform, or better, is compiled twice.

Decide per model, not per engine. That keeps the technique cheap, and it
means the bake pipeline only has to handle simple playback. It never has
to reproduce weighted blending.

### What the texture path costs

The caps table reports `MAX_VERTEX_TEXTURE_IMAGE_UNITS = 16`, which says
the vertex stage *can* sample a palette texture. It does not say the
sample is free. The original note treated the texture paths as a pure
win; they are not. They move cost, they do not remove it.

A uniform array lives in constant memory: small, cached, broadcast to
every invocation, effectively free to read. A palette texture is a memory
fetch per column:

- One `mat4` = **4** `texelFetch` calls, one per column.
- glTF skinning uses up to **4** joint influences per vertex.
- So up to **16** texel fetches per vertex, replacing what were
  constant-memory reads.

For a 10k-vertex character at 100 instances that is about 16M texel
fetches per frame. An M1 Pro will absorb it, but it is real bandwidth,
and on Apple's GL-on-Metal translation it is the part least likely to
match desktop-GL intuition.

The trade:

| | Uniform palette | Texture palette |
|---|---|---|
| Per-draw CPU cost | one 6400 B upload | none (or one shared upload) |
| Draw calls | one per instance | one instanced draw |
| Vertex-stage reads | constant memory (~free) | up to 16 fetches/vertex |

It pays off when upload count and draw-call count dominate, which is the
instance count this note is about. It is a *loss* for a handful of
characters, which is the other reason hero models should stay on Path 1.

If the fetch count becomes the problem, the compaction options below
attack it directly: `mat3x4` drops 4 fetches to 3 (−25%), and
dual-quaternion skinning drops it to 2 (−50%).

---

## Path 4 — not available on 4.1

**SSBO** (`layout(std430) buffer`) is OpenGL 4.3 / GLSL 4.30. It is the
modern "put a huge array of structs in a buffer" API, with friendlier
alignment than `std140`. Out of reach unless the engine moves past the
current 4.0 core shaders (`#version 400 core`) and the macOS 4.1
ceiling.

macOS is hard-capped at OpenGL 4.1. The cap is Apple's
`OpenGL.framework`, not a missing loader library, so installing a newer
GLFW or `zopengl` does not raise it. On this Mac the context string is
already `4.1 Metal - 90.5`: Apple's GL is a Metal translation, still
advertised as 4.1, so SSBO entry points stay null. Texture buffers and
UBOs are the portable 4.1 pair.

---

## Measured caps (this Mac)

Machine: MacBook Pro 14" (MacBookPro18,3), Apple M1 Pro, 16 GB unified
memory. Context created the same way as the games (`4.1 core`,
forward-compatible). Re-run with `zig build gl_caps-run`.

| Query | This Mac | Spec minimum (GL 4.1) | What it means for 100-joint palettes |
|-------|----------|------------------------|--------------------------------------|
| `GL_VERSION` | `4.1 Metal - 90.5` | 4.1 | Confirms the Apple-on-Metal 4.1 ceiling |
| `MAX_VERTEX_UNIFORM_COMPONENTS` | **4096** | 1024 | 100 mat4s = 1600; current uniform path fits |
| `MAX_UNIFORM_BLOCK_SIZE` | **65536** | 16384 | **10** palettes per UBO (6400 B each) |
| `MAX_TEXTURE_BUFFER_SIZE` | **268435456** texels | 65536 | **671,088** palettes in one TBO |
| `MAX_TEXTURE_SIZE` | **16384** | 16384 | Pose atlas: 16384 instance rows if width = 400 |
| `MAX_VERTEX_TEXTURE_IMAGE_UNITS` | **16** | 16 | Vertex shader can `texelFetch` a palette texture |

The TBO number answers "can 4.1 do hundreds of animated instances on
this Mac?" Yes. 256 M texels × 16 bytes (`RGBA32F`) is a 4 GiB
theoretical buffer. 16 GB of unified memory and the CPU animator will
give out long before the GL limit.

A 2D `RGBA32F` atlas of 400 × N holds 16,384 unique poses in one
texture. Hundreds is not even a large fraction of that.

So the local 4.1 implementation is not what prevents a crowd. The
100-call uniform loop and one-draw-per-model are.

---

## Vulkan / wgpu — does switching buy the headroom?

Raised 2026-08-16: convert `/Users/john/Dev/Dev_Rust/small_wgpu_core` to
Zig and leave OpenGL, on the theory that Vulkan or wgpu is how you get
past 4.1 and then instance hundreds of skinned models.

**On this Mac, "Vulkan" is still Metal.** There is no native Vulkan ICD.
wgpu defaults to the **Metal** backend. A Vulkan path means MoltenVK,
which is Vulkan translated to Metal. The GPU and the 16 GB of unified
memory do not change. What changes is the API surface and the size of
the rewrite.

`small_wgpu_core` was already on that better surface, and it used the
same 100-matrix uniform array:

```wgsl
@group(1) @binding(2) var<uniform> bone_transforms: array<mat4x4<f32>, MAX_BONES>;
```

That is a UBO-shaped bind-group slot, not a storage buffer, and not a
crowd path. wgpu's default uniform-buffer limit is 64 KiB, the same
10-palette box this Mac reports for `MAX_UNIFORM_BLOCK_SIZE`. The Rust
project had not solved "hundreds of independently posed instances"
either. It had solved "upload one palette without 100 API calls," which
GL 4.1 can also do, with `glUniformMatrix4fv` and a count, or with a
UBO.

Storage buffers, the SSBO equivalent, *are* a wgpu/Metal/Vulkan feature
GL 4.1 lacks. They are nicer to write than `texelFetch` of four columns.
They are not required for the instance counts this GPU can already feed
through a TBO.

### What a switch would cost

redfish already has what the Rust tree was aiming at: native glTF,
Cook-Torrance PBR, cubic-spline skinning, angrybot, level_01, and the
allocator and `Context` rules. `small_wgpu_core` stopped at "core plus
an animation example, shadows in progress." Porting it to Zig is a third
engine, not a conversion of the first. You would re-implement loading,
materials, the games, and the memory model on top of wgpu-native or a
Vulkan layer, then catch the current GL tree on features.

Vulkan is genuinely hard, and the difficulty is mostly front-loaded:
swapchains, sync, pipelines, descriptors. wgpu hides a lot of that,
which is why the Rust core got as far as it did. It does not hide the
fact that every system above the GPU context has to be written again.

### When a switch *would* be the right move

- A deliberate backend change (Metal/Vulkan/DX12) for compute, bindless,
  multi-queue, or non-Mac targets you care about more than the current
  GL games.
- Willingness to pause game work for months and treat redfish's GL tree
  as the reference, not the live engine.

It is not the move that unlocks hundreds of animated models on this Mac.
That is a texture-buffer or pose-atlas job plus instancing, on the engine
you already have, and this machine's 4.1 limits already allow it.

---

## Instancing vs. upload

`glDrawElementsInstanced` and `glVertexAttribDivisor` are in 3.3.
Per-instance `matModel`, as four `vec4` attributes with divisor 1, is
easy. A 100-matrix palette is not, since `MAX_VERTEX_ATTRIBS` is 16
`vec4`s.

So the split is:

- **Instance attributes:** model matrix, clip/time, palette offset.
- **Shared lookup table:** UBO (tiny), TBO, or 2D `RGBA32F`
  texture (the palette or the baked clip).

One mesh VAO, one texture or TBO bind, one instanced draw. That is the
shape for hundreds of instances.

---

## Three crowd problems, three answers

"Hundreds of instances at different points in their animation" is really
three different problems, and they need different machinery. Ordered by
cost to build, cheapest first:

### 1. Pose pool — N instances, K distinct poses (K ≪ N)

**The cheapest thing that works, and the smallest step from what this
tree already does.**

Hundreds of instances rarely need hundreds of *distinct* poses. A horde
of 200 enemies might be in 3 animation states, and within a state the eye
cannot tell 200 phases from 12. So evaluate **K** palettes per frame on
the CPU, upload K rows, and give each instance a pose index.

```
K = states × phase_buckets     // e.g. 3 × 8 = 24
CPU cost: 24 animator updates/frame, not 200
GPU:      24 rows in a TBO or atlas; instance attribute = pose index
```

Note what this is: `angrybot` today is **K = 1**. `EnemySystem` has one
shared `Animator`, so every enemy is in lockstep. This case is that same
architecture, generalized from one shared pose to a small pool of them.
No bake pipeline, no offline step, no fixed frame rate, no matrix lerp.
The live `Animator` keeps running with cubic-spline interpolation and
weighted blending fully intact. You just run it K times instead of N.

Tuning is a single number. K = 1 is today's lockstep. K = 24 already
looks like a crowd. K = N degrades gracefully into case 3.

The visible cost is that instances sharing a bucket are pose-identical.
Vary position, facing, and scale — angrybot already varies all three per
enemy — and raise `phase_buckets` until it reads as a crowd. Assign each
instance a stable random bucket at spawn rather than by index, to avoid
visible banding.

Build this first. It needs the
[engine split](#the-engine-blocker-model-owns-too-much) and nothing else.
Not even a texture, if K is small enough that K uniform uploads per frame
is acceptable.

### 2. Same clips, different times — baked clip sheet

Horde, wildlife, and background NPCs, all playing from a fixed clip
library. Bake sampled frames into a 2D `RGBA32F` texture once; see
[3b](#3b-2d-float-texture-the-usual-video). Per instance: a clip row-base
and a time. The GPU fetches two rows and blends. The CPU animator leaves
the per-instance loop entirely.

Choose this over the pose pool when you want genuinely continuous
per-instance phase, with every instance at its own point in the clip, and
you can accept sampled fidelity. The cost is an offline bake step and
losing runtime blending for those models.

### 3. Unique blends / IK / ragdoll per actor

Each pose has to actually be evaluated. Keep `Animator` on the CPU, write
every palette into one TBO or one atlas row, and draw instanced. The win
is draw-call and uniform-call count, **not** animation math. The CPU
still runs N animators, which is exactly what
[Measure first](#measure-first) warns will be the wall.

Only reach for this when the poses are genuinely unique. If they are not,
case 1 does the same job for a fraction of the CPU.

### And the hero

A handful of principal characters need none of the above. Path 1, one
uniform palette upload and one draw, is both simpler and *faster* per
character than a texture fetch path; see
[What the texture path costs](#what-the-texture-path-costs). Keep the
player on it.

---

## Compaction (optional, later)

If the uniform or UBO budget ever hurts for a single palette:

- Skinning matrices are affine: the last **row** is `0 0 0 1`, so one row
  of the 4×4 is redundant. Dropping a row is not the same as dropping a
  column, and that is where this trick usually goes wrong. **Store the
  transpose.** The transposed matrix's columns are the original's rows,
  so discarding the original's last row means discarding the transpose's
  last column. That leaves three `vec4` columns: a `mat3x4`, which is 48
  bytes in `std140` as three 16-byte-aligned `vec4`s. The shader reads
  three `vec4`s and transposes back, or equivalently builds
  `mat4(c0, c1, c2, vec4(0,0,0,1))` from the transposed rows and uses it
  accordingly. That is 25% less data, and one fewer `texelFetch` per
  joint on the texture path.

  Storing it the naive way, as three of the original's *columns*, loses
  real data, because the discarded fourth column is the translation.

  Note the asymmetry: in `std140` a `mat4x3` does **not** shrink, since
  four `vec3` columns each pad to 16 bytes and it stays 64. Only the
  `mat3x4` orientation saves anything.
- Dual-quaternion skinning is two `vec4`s per joint. Half the bandwidth,
  different shader math, and no scale unless you add a third vector.

Neither is required to escape the 100-call loop.

---

## Recommendation

Stay on `#version 400 core` / OpenGL 4.1.

**Done**

0. The 100-call loop was an API-wrapper gap, not a spec limit. One
   `glProgramUniformMatrix4fv` with `count = MAX_JOINTS`, shipped in
   `4147f1e`.

**Do next, in this order**

1. **Stop the two uploads that should not happen.** Guard the palette
   upload in `Model.draw` on `skin_index != null` — one line, and every
   static prop currently sends 6400 bytes of identity matrices per frame.
   Then hoist the palette and node walk out of the per-enemy loop in
   `EnemySystem.drawEnemies`. Local, no architecture, immediate.
2. **Split per-instance state out of `Model`.** `Animator` and the
   instance transform move to a `ModelInstance`, and `Model` keeps the
   shared meshes and `GltfAsset`. Nothing else on this list is
   expressible until this exists. Build order and the
   `active` / `baked` / `static` pose-source union are in
   [Shaping the split](#shaping-the-split-pose-source-and-instancing).
   Instancing lands there too, and step 3 of that list is worth doing
   before the pose pool.
3. **Measure.** Draw calls, uniform uploads, CPU animation, vertex
   processing. Find which one is the wall at your target count before
   building for it.
4. **Pose pool (K distinct poses, K ≪ N).** The cheapest crowd, and the
   smallest delta from today's shared-animator `EnemySystem`. Keeps the
   live animator and all its blending. Try this before any texture work.

**Then, if measurement says so**

5. Pick the texture layout from the crowd type: a baked clip sheet when
   instances share clips and you want continuous per-instance phase, or a
   TBO / pose atlas when every pose is genuinely unique. Do not fear the
   texture itself, since GLSL 4.10 lookup rules return raw floats from
   `RGBA32F` and `RGBA16F`; use `texelFetch`. But price the vertex-stage
   fetches first, because the path is a loss for small instance counts.
6. Tier by fidelity, not by engine. Hero characters stay on the uniform
   palette; the horde takes the sampled path. Matrix lerp between baked
   frames is an approximation that is invisible at distance and wrong in
   close-up.

**Do not**

7. Do not add a `std140` UBO. On this machine it buys neither component
   headroom, with 2496 spare, nor a meaningfully cheaper rebind than
   Path 1 already provides. Revisit only for a non-Apple, spec-minimum
   target.
8. Leave SSBOs until there is a non-macOS / GL 4.3+ target.
9. Do not switch to Vulkan or wgpu to unlock instance counts on this Mac.
   The 4.1 TBO and atlas limits already cover hundreds of poses, and the
   blocker was never the API. It was `Model` owning the animator. A
   backend change is a separate, much larger bet.

---

## Pointers

- Current upload: `src/core/model.zig` `Model.draw` — one
  `setMat4Array` call, then `drawNodes` walks the tree.
- Wrapper: `src/core/shader.zig` `setMat4Array` (takes `[]const Mat4`,
  derives `count` from `.len`). `setMat4` remains for single matrices.
- Instance coupling: `src/core/model.zig` `Model` struct (owns
  `meshes` *and* `animator`); `games/angrybot/enemy.zig`
  `EnemySystem.enemy_model` + `drawEnemies` — the shared-pose case.
- Storage: `src/core/animator.zig` `joint_matrices: [MAX_JOINTS]Mat4`,
  `src/math/mat4.zig` (`extern struct`, column-major).
- Joint count: `src/core/constants.zig` `MAX_JOINTS = 100` — must match
  `const int MAX_JOINTS` in every animated shader, or the single
  count-form upload fails with `GL_INVALID_OPERATION` (the old
  per-element loop degraded silently instead).
- Shader declaration: `examples/animation_example/player_shader.vert`
  line 15, and the copies in `examples/demo_app/shaders/`,
  `games/level_01/shaders/`, `games/angrybot/shaders/`.
- GLSL 4.10: uniforms / uniform blocks; texture lookup functions
  (`texelFetch`, `samplerBuffer`).
- Caps probe: `examples/gl_caps/main.zig`, `zig build gl_caps-run`.
- OpenGL 4.1 API: `UniformMatrix4fv` count; `MAX_VERTEX_UNIFORM_COMPONENTS`;
  `MAX_UNIFORM_BLOCK_SIZE`; `MAX_TEXTURE_BUFFER_SIZE`; Table of sized
  internal formats (`RGBA32F` vs unsigned-normalized `RGBA8`).
