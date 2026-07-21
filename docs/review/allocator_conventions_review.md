# Allocator Conventions Review — 2026-07-14

Question under discussion: should component `init()` functions take
`std.mem.Allocator`, `*std.heap.ArenaAllocator`, or offer both flavors?
Prompted by `texture.zig`, which currently has one of each:
`initFromGltf(io, arena: *ArenaAllocator, ...)` and
`initFromFile(io, allocator: Allocator, ...)`.

Goals: follow Zig idioms, reduce cleanup boilerplate, avoid patterns that
invite errors. Not writing a library for others — personal engine.

---

## TL;DR

**Policy at the top, mechanism at the bottom.** Low-level components
(texture, mesh, model) take `std.mem.Allocator` and stay strategy-agnostic;
high-level owners (scene, resource manager) decide what backs it and own the
lifetime. Internally, a component may still use an arena in two distinct
ways:

- **Scratch arena** — created and destroyed within a function for temporary
  buffers (decode buffers, path strings) that die before return.
- **Arena-in-a-box** (`std.json.Parsed` style) — an arena hidden inside the
  returned result that owns the result's allocations; `deinit()` frees
  everything in one call. Note: this arena *outlives* the call as the
  result's owner — it is not the temporary-buffer pattern.

---

## Recommendation (agreed direction)

Keep `std.mem.Allocator` in every signature and signal the ownership
contract with the **parameter name**:

- `arena: Allocator` — component assumes bulk cleanup; it never frees
  individually and offers no memory `deinit`.
- `gpa: Allocator` — component will free what it allocates and provides
  `deinit`.

Organize arenas by **lifetime tier** at the composition roots; keep explicit
cleanup only for resources arenas cannot free (GL objects). Skip the
dual-flavor init idea — the `Allocator` interface *is* the two flavors.

### Lifetime tiers

| Tier | Backing | Freed when | Typical contents |
|------|---------|-----------|------------------|
| App | GPA or arena | process exit | engine singletons, shader cache |
| Scene | `ArenaAllocator` owned by the scene | scene unload | models, meshes, textures, animation data |
| Frame / scratch | `ArenaAllocator`, `reset(.retain_capacity)` per frame or per load operation | every frame / end of operation | decode buffers, path joins, temp strings |

### Rules of thumb

1. Signatures take `Allocator`; the parameter name is the contract.
2. **Absence of `deinit` = arena-owned memory.** Components allocated from
   the scene arena have no memory cleanup to offer. Also erases `errdefer`
   partial-init cleanup chains — the biggest boilerplate win.
3. **Explicit cleanup only for non-memory resources.** `deleteGlObjects` is
   the right shape: not named `deinit`, not about memory, must run regardless
   of allocation strategy. ResourceManager (Plan 015) is the natural owner:
   the factory tracks GPU handles, the arena owns bytes.
4. **Loaders get a scratch allocator for transients** — second
   `scratch: Allocator` param or an internal temp arena in `GltfAsset` reset
   after `buildModel()`.

---

## Why not `*ArenaAllocator` in signatures

- **Defeats the interface.** `Allocator` exists so the caller picks the
  strategy. A concrete-arena param can't accept `std.testing.allocator`, a
  `FixedBufferAllocator`, or a debug GPA — losing leak and use-after-free
  detection for that subtree.
- **Viral.** Everything below must take the arena or convert back.
  `initFromGltf` converts on its first line anyway — the concrete type buys
  one line of documentation, then erases itself.
- **Doesn't deliver the implied guarantee.** Arenas free *memory*. A
  `Texture` holds `gl_texture_id`; the arena frees the struct while the GPU
  texture leaks. "Arena in the signature = no cleanup needed" is exactly the
  false impression that produces VRAM leaks.
- **Conflates transient and persistent lifetimes.** (Corrected 2026-07-16
  after code re-read.) In `initFromGltf`, two per-texture transients are
  retained until scene teardown even though both are dead after
  `createGl2DTexture`:
  1. **stb's decoded-pixel buffer** — the cleanup code is *correct*
     (`image.deinit()` runs and zstbi's `mem_allocations` bookkeeping is
     properly cleared), but `zstbi.init` was given the arena allocator and
     the pixels are no longer the arena's top allocation when the deferred
     deinit runs (`allocator.create(Texture)` lands above them), so the free
     is a no-op. Correct code, retained anyway — the purest example of the
     transient/persistent conflation.

     *Precision note (2026-07-16, from reading Zig 0.16
     `ArenaAllocator.zig` `free()`):* arena free is not unconditionally a
     no-op. It reclaims **iff the freed slice is the most recent
     allocation** (top of the bump stack), rewinding `end_index`; otherwise
     it returns without freeing ("Not the most recent allocation; we cannot
     free it"). The `.release` ordering on its cmpxchg is atomic
     memory-ordering semantics, not memory being released to the parent
     allocator. So: LIFO frees reclaim, everything else is retained until
     `deinit()`/`reset()`. None of the frees in the texture path are LIFO.
  2. **the base64 `data_buffer`** — never freed by anyone; see the ownership
     bug below.
  `c_path` is fine: it has `defer free` and is tiny. Big scene → megabytes of
  dead decode buffers retained until scene teardown.

  **Ownership bug found during this correction:** the comment at
  `texture.zig:165` — "zstbi will own the data_buffer and free it on image
  deinit" — is wrong. `stbi_load_from_memory` decodes *from* the input
  buffer into new stb-allocated memory; `image.deinit()` frees only the
  decoded pixels (`zstbi.zig:343`), never the input. Under a gpa,
  `data_buffer` is a true leak; the arena currently masks it.

## Why not two init flavors

Doubles the API surface for zero safety; the interface type already gives
callers the choice. Param naming + doc comment provides the compile-time
signaling at no cost. Overkill even for a library, definitely for a personal
engine.

Note this is a different question from *two allocator parameters* on one
function (below) — two flavors means duplicate entry points for the same
work; two parameters means one entry point whose transients and results have
different lifetimes.

## Scratch allocation strategy (naming + direction decided; implementation pending)

**Decided:** the allocator pair is named **`alloc` + `temp_alloc`**
(2026-07-16). Keeps Odin's unmarked-default asymmetry, and `temp_alloc`
self-documents that it is an allocator (vs. bare `scratch`/`temp`).
**Direction (2026-07-18):** the pair travels inside a `Context` struct in
`src/core` (see "Context struct" below); arenas are owned by the tier
owners (World et al.), and contexts are rebound per tier — resolving the
earlier ownership question. Remaining open: `random`/logger fields, and the
implementation itself.

**Design direction note:** the engine core was built bottom-up
(components first); the shift now is toward top-down — components working
together in the context of a *game*, which is what actually defines memory
as a resource with distinct lifetimes (process / scene / model / frame).
The lifetime tiers in this document are the memory-facing half of that
shift; `examples/bullets/world.zig` is the first place the top-down
structure exists in code.

Problem: when the incoming allocator is an arena, transient allocations
(decode buffers, parse scratch) persist unless freed in LIFO order — which
in practice they never are. How should temporaries be separated from
long-lived allocations?

**Two allocators is an established idiom, not a hack.** Odin bakes
`context.allocator` and `context.temp_allocator` into the language's calling
convention; Jai does the same; the Zig compiler passes `gpa` and `arena`
side by side through Sema; and the classic game-engine memory model
(permanent arena + per-frame temp arena) is the same pattern.

Strongest precedent (noted 2026-07-18): **Zig 0.16 bakes the pair into
`main()` itself.** `std.process.Init` provides every application
`arena: *ArenaAllocator` ("permanent storage for the entire process, cleaned
automatically on exit"), `gpa: Allocator` ("for temporary heap allocations",
leak-checked in Debug), and `io: Io` — structurally the same bundle as the
proposed `Context {alloc, temp_alloc, io}`, one tier up; `world.zig` already
consumes it. Note the role inversion: at process scope the *arena* is the
permanent/result allocator and the *gpa* is the temporary one, while at the
scene tier it flips — same contract names, opposite mechanisms per tier,
which is exactly why the pair is named by contract (`alloc`/`temp_alloc`)
rather than mechanism. The hack
feeling comes from imagining every init growing a second parameter — the
clean version scopes it: **a `scratch: Allocator` parameter appears only on
functions that genuinely produce throwaway work** (texture decode, glTF
buffer parsing — a handful of functions here).

Candidate approaches:

1. **Scoped second parameter** (`scratch: Allocator`) — explicit, no hidden
   state; only on the few functions with real transients.
2. **Internal page-backed temp arena** (`std.json` style) — function creates
   and destroys its own scratch arena; zero signature changes.
   **Trap:** the internal arena must be backed by a real allocator
   (`page_allocator` / gpa). Backing it with the caller's arena reclaims
   nothing — the temp arena's `deinit` frees its nodes back to the child
   allocator, and those frees are non-LIFO no-ops on the outer arena.
3. **`GltfAsset`-owned scratch arena** — a second, page-backed arena next to
   the model arena; texture/parse transients allocate from it and
   `buildModel()` resets or destroys it after GL upload. One arena reused
   across all of a model's textures, one reset point, lifetimes visible in
   the type that owns them.
4. **Context struct** (added 2026-07-16) — bundle the capabilities that
   already travel together into one explicit parameter:

   ```zig
   pub const Context = struct {
       io: Io,
       alloc: Allocator,      // result lifetime — owned by what you're building
       temp_alloc: Allocator, // dead by end of call; owner resets — never store
   };
   ```

   This is the Zig translation of Odin's implicit
   `context.allocator` / `context.temp_allocator` (Zig rejected implicit
   context, so pass the struct explicitly). Discovered precedent in-repo:
   `examples/bullets/world.zig` already implements the tier structure —
   `root_allocator` (gpa) + `scene_arena` recreated on every scene switch —
   and threads `(io, allocator, input)` into each scene init, i.e. the
   bundle is already forming naturally. Bonus: the next cross-cutting
   capability (after 0.16's `Io`) doesn't have to touch every signature.

   Naming: name by *relative contract*, not backing. "perm" is wrong (the
   first allocator may be scene-arena- or gpa-backed; its contract is
   "outlives this call", not "forever"); `arena_alloc` names the mechanism —
   same mistake as `*ArenaAllocator` in signatures. Odin's cue: the default
   allocator is **unmarked**, only the temporary one is marked.
   → Decided: `alloc` + `temp_alloc` (see section header).

   Disciplines if adopted:
   - Scratch reset contract: the owner (e.g. World) resets scratch per frame
     or per load operation; callees never retain scratch pointers past the
     call. This rule compiles fine when violated — document it on the field.
   - No god-object creep: context holds **capabilities** stable for a
     lifetime tier (io, allocators). Per-frame data stays in
     `RenderContext`; `input` stays a separate param.

Pragmatics: the model arena is per-`GltfAsset` and destroyed by
`Model.deinit`, so retained decode junk dies with the *model*, not the
scene — worst case roughly compressed size + decoded RGBA per loaded model
(tens of MB, transient). Acceptable for now; would bite with many resident
models, texture hot-reload, or a move to a longer-lived shared arena.
File under "correct design, unhurried priority."

**Current leaning (2026-07-18): two arenas.** `alloc` backed by a long-lived
arena (cleaned at scene end / exit), `temp_alloc` backed by an arena reset at
checkpoints (frame end; optionally after scene load). The classic engine
permanent+transient memory model. Verified against Zig 0.16
`ArenaAllocator.reset()`:

- `.retain_capacity` reuses memory and *consolidates* chunks — after a few
  resets it converges to one chunk and stops touching the backing allocator
  entirely (amortized O(1) reset). The "long-lived pool serving short-lived
  objects" assumption holds.
- `.retain_with_limit = N` keeps up to N bytes, returning the excess.
  Preferred for `temp_alloc`: steady-state frame churn stays warm while
  scene-load spikes (decode buffers, tens of MB) get released instead of
  staying committed forever under plain `retain_capacity`.
- A `false` return only means the consolidation realloc failed; the arena is
  fully reset and functional, just slower to re-warm. Ignorable.

Disciplines:
- **The reset point is the contract.** Frame-end reset covers both frame
  temps and load transients; anything surviving a reset must come from
  `alloc` (the existing "never store temp_alloc pointers" rule, with a
  concrete enforcement moment).
- **Debug variant:** in Debug, reset temp with `.free_all` backed by
  `process.Init.gpa` so use-after-reset touches freed, leak-checked memory
  instead of stale-but-valid pool bytes; Release uses `.retain_with_limit`.

Note the role axis: the deciding question for arena-vs-gpa is not lifetime
*length* but **whether individual frees ever happen**. Never-freed
long-lived → arena (why `process.Init` calls its arena "permanent");
individually-freed temporaries → gpa (leak checking); bulk-reset
temporaries → arena again. Games live in the last cell, hence two arenas.

## Context struct (direction agreed 2026-07-18)

A `Context` in `src/core`, passed by value:

```zig
pub const Context = struct {
    io: Io,
    alloc: Allocator,      // caller-owned result lifetime
    temp_alloc: Allocator, // callee scratch; flushed at the owner's checkpoint
    // random: std.Random  // leaning include — see below
    // logger              // deferred — see below

    pub fn withAlloc(self: Context, alloc: Allocator) Context { ... }
};
```

**The contract:**
- `alloc` — the callee allocates objects the *caller* will own; the caller
  decides the lifetime by choosing what backs `alloc` at each call site.
- `temp_alloc` — callee scratch pad. Precise guarantee: *temp allocations
  remain valid until the owner's next checkpoint (frame end), never sooner
  than the callee's return.* This legalizes returning temp-backed data
  (decoded pixels, formatted strings) for the caller to consume or copy
  within the frame — the idiomatic Odin/Jai temp pattern.

**The Context is relative, not absolute.** Tiers (app / scene / per-model /
frame) live in their *owners* (World holds the arenas); callers derive a
rebound copy at each boundary (`ctx.withAlloc(model_arena.allocator())`) —
Odin's copy-and-override context scoping, made explicit. The struct stays
two-slot no matter how many tiers exist. In practice: app-vs-scene is the
main `alloc` distinction; frame-tier does the volume on `temp_alloc`.

**When does something deserve its own arena? An arena per unload unit**
(2026-07-18, from demo_app model cycling). If X can be unloaded/swapped
independently at runtime, X gets its own arena; otherwise X's memory is
retained until the enclosing tier resets and repeated swaps grow
monotonically. angrybot: models die with the scene → scene arena suffices.
demo_app: models are swappable → per-model arena tier. Same callee code;
the caller's backing choice expresses the lifetime. Implementation: reuse
one model arena with `reset(.retain_capacity)` between models (capacity
converges to the largest model); switch sequence mirrors scene switch —
`model.cleanUp()` → reset → load next via `ctx.withAlloc(...)`. Watch-item:
survivors of a swap (camera, UI state, the model list) must come from the
enclosing tier, not the swapped tier.

**Corollary — region lifetimes must nest or be disjoint, never interleave**
(2026-07-18, found live in demo_app `run_app.zig` model reload). The
load-new-model-then-free-old pattern (kept deliberately so a failed load
falls back to the old model) makes two model generations overlap — illegal
in one shared arena: the code loaded the new model from the model arena,
then reset that arena, installing a dangling pointer. Failure is *delayed*,
not loud: `.retain_capacity` keeps chunks warm, so the new model reads fine
until the next reload's allocations overwrite it (the use-after-reset class
the Debug `.free_all` variant exists to expose). Two coherent fixes:
1. **Cleanup-first** (one arena): `cleanUp` → reset → load. Loses the
   failed-load fallback.
2. **Ping-pong two model arenas** (keeps fallback): load the new generation
   into the inactive arena; on success `cleanUp` old → reset old's arena →
   swap active. No extra peak memory vs. load-first intent (two models were
   already resident during load); both arenas converge via
   `retain_capacity`. Classic double-buffered region pattern.
Chosen for demo_app: ping-pong (fallback behavior is intentional).

**Lifetime scope structs (2026-07-18).** The tier-as-type pattern: bundle an
unload unit's arenas with the objects they govern —

```zig
const ModelScope = struct {
    arenas: Arenas,
    model: ?*Model = null,

    pub fn ctx(self: *ModelScope, io: Io) Context {
        return self.arenas.context(io);
    }
    // lifecycle methods (load/reload) live here so the
    // cleanUp → reset → load ordering is structural, not per-call-site
};
```

Generalizes to `PhaseScope`, `EnemyScope`, etc. — grouping objects by
*lifetime* rather than kind, the core regional-memory principle. Rules:
- **Caching a `Context` in the scope is safe iff the arenas live behind a
  stable pointer that travels with it** (refined 2026-07-20, from demo_app's
  working `ModelScope`). With `arenas: *Arenas` heap-allocated, the cached
  context points into a stable heap object, and the `(arenas, context)` pair
  stays consistent through scope copies/swaps — generation swaps merely
  relabel which scope references which `Arenas`. Embedding `Arenas` *by
  value* remains unsafe (self-referential, move-breaks). When in doubt, mint
  on demand from a pointer receiver — three field copies, nothing to cache.
- One scope per **unload unit** (see rule above), and the group must have a
  moment when everything in it is dead. Continuous per-item churn (enemies
  dying one at a time forever) has no legal reset point → use a fixed pool
  with slot reuse instead, or accept retention until the group boundary.
- Naming: prefer `Scope`/`Region` over `XContext` — "Context" now means the
  capability courier specifically.

**Consequence — the GltfAsset arena seam dissolves.** The caller-owns-
lifetime contract inverts today's design where `GltfAsset.init` creates an
arena and transfers it to Model. Under Context, GltfAsset allocates from
`ctx.alloc` and owns nothing; `Model.deinit` stops destroying arenas. This
also improves model cycling: demo_app binds `alloc` to a per-model arena it
recycles; angrybot binds the scene arena — same callee code, caller-chosen
lifetime. (Reshapes the Tier 2 checklist items when implemented.)

**Optional fields:**
- `random: std.Random` — leaning **include** (Odin precedent). Zig has no
  ambient RNG, so the state must be threaded somewhere anyway; Context beats
  scattered `DefaultPrng`s (cf. existing `src/core/random.zig`). Seed once
  and log the seed → reproducible runs. Caveat: single-stream determinism
  requires deterministic call order; per-system streams are the serious
  version if replay ever matters.
- logger — **deferred**. `std.log` (comptime-scoped, global) covers current
  needs; a Context logger earns its slot when a per-instance sink appears
  (e.g. in-game console). Adding a field later touches only creation sites,
  not signatures — deferring is free, which is the Context's meta-benefit.

**Boundary rule:** capabilities in, per-frame data out. `delta_time`,
input, camera stay in `RenderContext`/params; Context holds only what is
stable for a lifetime tier. This keeps it copyable and rebindable.

### Committed (2026-07-18): top-down memory model

Decision: commit to the top-down model — lifetimes and cleanup policy are
owned by the game structure (World/scene), not by individual components.
First `Context` implementation landed in `src/core/context.zig`.

**Milestone (2026-07-18): bullets fully migrated and verified.** World owns
`alloc_arena` + `temp_alloc_arena`, mints the Context, and on scene switch
runs `scene.cleanUp()` → reset both arenas (correct ordering); scenes and
ResourceManager converted to `ctx.alloc` and `cleanUp()` (memory `deinit`s
removed). Compiles, runs, exits with no gpa leak complaints. Known
remainder: no call sites use `ctx.temp_alloc` yet, so all transients
(texture decode buffers etc.) still land in the long-term arena — drains
incrementally as loaders adopt `temp_alloc` (Tier 1 items); each adoption
pays off immediately since scene switch already resets the temp arena.

**Field types — owner/context split.** Implementing Context surfaced the
question "don't `alloc`/`temp_alloc` need to be `ArenaAllocator` so they can
be reset?" Resolution: reset never travels with the Context.
- The **owner** (World) holds the concrete `ArenaAllocator`s and is the only
  party that resets, at checkpoints only it knows.
- The **Context** carries `Allocator` interface values (stable pointers into
  the owner's arenas, safe to copy).
- A by-value `ArenaAllocator` field is a correctness trap: copying the
  Context copies mutable chunk-list state; diverged copies lose allocations
  and double-free on teardown.
- `std.process.Init` models the same split: main() — the owner — receives
  the concrete `*ArenaAllocator`; downstream code sees `Allocator`.
- The interface also (a) makes reset authority structural — callees cannot
  flush temp mid-frame — and (b) keeps the Debug gpa-backing variant
  possible.
- Wiring caveat: `.allocator()` captures the arena's address; owner arena
  fields must not move after contexts are minted (heap-allocated World is
  fine; in-place re-init on scene switch keeps the address valid).

**Resolved (2026-07-18): arenas stay out of Context — permanently.** The
closing argument: there are many allocator flavors (arena, gpa, testing,
fixed-buffer, `process.Init`'s arena), and which one backs a Context must
not be baked into the type. Context's contract is purely semantic (`alloc`
= caller-owned result lifetime; `temp_alloc` = flushed at owner's
checkpoint); the mechanism lives entirely behind the `Allocator` interface,
with the owner. Storing arenas in Context was also rejected for duplicate
state (`alloc` + `alloc_arena` must agree, and `withAlloc` breaks the
pairing) and reset-authority diffusion. For owner-side ergonomics with
multiple arenas, use owner helper structs instead — `Arenas` (owns tier
arenas, mints Contexts, one reset point) and `SwapArena` (ping-pong
generations for swap tiers). Mnemonic: **many contexts, one owner.**

**Deinit cleanup policy.** The framework-vs-library conflict resolves in
favor of framework: objects inside a lifetime policy don't own their memory
cleanup. The earlier deinit work wasn't wasted — it produced the inventory
of external-resource holders, which survives as the `deleteGlObjects`
surface.
- [ ] Remove memory-only `deinit`s (delete, don't comment out — dead code
      invisible to lazy analysis rots; see CameraGimbal / `Texture.clone`)
- [ ] Remove stored allocator fields from objects that no longer free
- [ ] External-resource cleanup naming (decided 2026-07-18): **`cleanUp()`**
      on aggregates (Scene, ResourceManager, Model) — general enough for GL
      objects plus future audio handles etc., and clearly separated from
      `deinit`'s idiomatic "release everything, object invalid" meaning.
      Leaves keep precise names for the one resource they hold
      (`deleteGlObjects` on Texture/Mesh/Shader); aggregate `cleanUp()` fans
      out to them. Contract: releases external resources only, never
      memory; must run *before* the owning arena resets/deinits; call once.
- [ ] Exceptions: gpa-created heap objects (e.g. `Camera` —
      `allocator.create` + destroying `deinit`) keep their pattern until
      moved into an arena tier

Related but undecided: how to resolve the base64 `data_buffer` ownership bug
(see Tier 1) — immediate `defer free` (no-op today, correct under any future
allocator) vs. waiting to route it through whichever scratch approach wins.

---

## Prior art surveyed

- **Zig stdlib** — `Allocator` everywhere; arena as *internal implementation
  detail*. Canonical: `std.json.Parsed(T)` creates an internal arena, parses
  into it, `deinit()` destroys the whole arena ("arena-in-a-box"). Language
  trend: unmanaged containers (`ArrayList` is unmanaged as of 0.15+) — don't
  store allocators, pass them through; composes naturally with
  arena-at-the-root.
- **TigerBeetle** — neither arenas nor per-object cleanup: TigerStyle
  mandates allocating everything at startup with static limits, zero
  allocation after init. Solves "who frees what" by making the question
  disappear — same instinct as the scene arena, at process granularity.
- **Ghostty** — the model adopted here: allocator params/fields named by
  semantic contract (`gpa` vs `arena`); signatures stay interface-typed.
  Config parsing uses an internal arena; long-lived state uses the gpa.
- **Bun / zls** — per-unit-of-work arenas (per parse, per document) reset
  between units; the "frame allocator" under another name.

---

## Known costs of committing to arenas (accepted trade-offs)

- **Use-after-free is masked, then time-shifted.** Arena memory stays valid
  until scene teardown; a dangling pointer "works" all scene, then explodes
  at scene switch. Countermeasure: debug builds occasionally back the scene
  arena with a GPA — only possible because signatures take `Allocator`.
- **Monotonic growth.** Arenas never reuse within their lifetime; per-frame
  allocations routed into the scene arena are a slow leak. The frame-tier
  arena with `reset(.retain_capacity)` is the discipline that prevents it.
- **Leak detection is moot** on arena-owned paths — acceptable since there
  are no individual frees to forget by design.

---

## Component fix list (surveyed 2026-07-14)

Structural note that shapes the list: the model-loading arena has exactly two
legitimate owners — `GltfAsset.init` *creates* it ("will be owned by the
model") and `Model.deinit` *destroys* it. Owners may hold the concrete
`*ArenaAllocator`. Every component in between converts to `Allocator` on its
first line and should take `Allocator` in its signature.

### Tier 1 — signature fixes: `*ArenaAllocator` → `arena: Allocator`

Mechanical changes, contained inside `src/core` (all callers are in the
asset-loading path):

- [x] **`texture.zig`** — fully converted to `Context` (2026-07-18): decode
      transients (stb pixels via `zstbi.init(ctx.temp_alloc)`, base64
      `data_buffer` with proper `defer free`, `c_path`) on `temp_alloc`;
      `Texture` struct on `alloc`; wrong zstbi ownership comment removed;
      `clone(alloc)` repaired
  - [ ] drop the now-unused `ArenaAllocator` import (`texture.zig:8`)

### Review findings after Context migration (2026-07-18)

Core + bullets migrated and reviewed. Verified safe: glTF parser `dupe`s
every retained string, so nothing references temp-allocated `file_contents`;
GLB binary chunk is copied into `alloc`; runtime-read `buffer_data` stays
long-term. Open items:

- [x] **Bug fixed:** `loadCustomTextureFromFile` `full_path` now freed via
      `temp_alloc` (was `alloc` — allocator mismatch)
- [x] Vestigial inner arena removed from `GltfAsset.init` — everything
      allocates from `context.alloc` directly
- [x] `setCustomTextures` `flag_name` now uses a stack `bufPrintZ` buffer —
      no allocation in the draw path
- [x] Rotted `Model.deinit` comment block, no-op `Animator.deinit`, dead
      `getCustomTextures` (zero callers), and stale `addTexture`
      `self.arena` reference all deleted; unused `ArenaAllocator` imports
      removed from asset_loader/texture/animator
- [x] JSON DOM evicted: `parseGltfJson(alloc, temp_alloc, buffer)` — DOM
      parsed from `temp_alloc`, retained data duped into `alloc`
- [ ] Migrate remaining old-signature callers (animation_example,
      scene_tree, demo_app, skybox, angrybot, level_01); consider a
      `Context.simple(io, alloc)` bridge (temp_alloc = alloc) for mechanical
      conversion ahead of each app growing a World. `zig build check` fails
      until these are done.
- [ ] **`mesh.zig`** — `Mesh.init` (`mesh.zig:33`),
      `MeshPrimitive.init` (`mesh.zig:121`)
  - [ ] change params to `arena: Allocator`
  - [ ] drop `Mesh.deinit` (it only forwards to `deleteGlObjects`; memory is
        arena-owned — callers should call `deleteGlObjects` directly)
- [ ] **`animator.zig`** — `Animator.init` (`animator.zig:271`)
  - [ ] change param to `arena: Allocator`
  - [ ] drop the stored `arena: *ArenaAllocator` field (only
        `arena.allocator()` is ever used; `ManagedArrayList` already carries
        its allocator for runtime appends)
  - [ ] delete the no-op `deinit` (`animator.zig:311`) — absence of deinit
        *is* the arena-owned signal

### Tier 2 — arena owners (keep concrete type, tidy the seam)

- [ ] **`asset_loader.zig`** (`GltfAsset`) — creator of the arena; keeps the
      `*ArenaAllocator` field. Fixes:
  - [ ] pass `arena.allocator()` (as `Allocator`) down to Mesh/Animator/
        Texture instead of the concrete pointer
  - [ ] add a scratch arena for loader transients, reset (or destroyed)
        after `buildModel()` — fixes decode-buffer retention
  - [ ] `deinit` only forwards to `deleteGlObjects` — call that directly and
        drop `deinit`
- [ ] **`model.zig`** (`Model`) — destroyer of the arena; keeps the
      `*ArenaAllocator` field. Fixes:
  - [ ] restructure `deinit` into `deleteGlObjects()` (mesh + gltf_asset GL
        cleanup) followed by arena teardown; remove the `animator.deinit()`
        call once that no-op is deleted

### Tier 3 — naming pass (`gpa:` / `arena:`), opportunistic

Components that allocate with a gpa contract (they free what they allocate);
rename the param to `gpa:` as files are touched — no big-bang rename:

- [ ] `camera.zig`, `camera_gimbal.zig` (heap-allocate self, deinit destroys)
- [ ] `resource_manager.zig` (owner/factory; Plan 015 reshapes it anyway)
- [ ] `sound_engine.zig`
- [ ] shapes: `cubeboid.zig`, `sphere.zig`, `square.zig`, `plane.zig`,
      `lines.zig`, `skybox.zig`, `shape.zig` — verify each `deinit` frees
      what its init allocates; drop the unused `ArenaAllocator` import in
      `plane.zig:9`. Long-term these become ResourceManager-created
      (Plan 015)

### Cross-cutting

- [ ] Introduce the scene-level arena at the scene/game layer (scene owns an
      `ArenaAllocator`, passes `arena.allocator()` down)
- [ ] Add a frame/scratch arena (`reset(.retain_capacity)`) for per-frame
      allocations
- [ ] Route GPU-object cleanup through ResourceManager (Plan 015) so "arena
      owns bytes, factory owns handles" is structural
- [ ] Debug option: back the scene arena with a GPA to surface
      use-after-free during development
- [ ] Optional/future: revisit the custom `ManagedArrayList` wrapper —
      upstream Zig has moved to unmanaged containers (allocator per call),
      which composes better with arena-at-the-root

### Suggested order

1. Tier 1 bottom-up (`texture` → `mesh` → `animator`) — pure signature
   changes, `zig build check` green after each file
2. Tier 2 (`asset_loader`, then `model`) — seam + ownership cleanup
3. Scratch arena for loader transients
4. Tier 3 naming and shape audits, opportunistically or with Plan 015

## Drive-by finding

`Texture.clone()` (`src/core/texture.zig:139`) references `self.allocator`,
a field that does not exist on `Texture` — dead code surviving via lazy
analysis, same family as the CameraGimbal findings in
[movement_usage_review.md](movement_usage_review.md) (item 5's
`refAllDeclsRecursive` guard would catch this too).
