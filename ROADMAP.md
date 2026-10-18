# Roadmap

what Prism plans to add next. this is a list, not a schedule: nothing here has a
date, and the shape of anything unbuilt is still open. for what exists today see
[README.md](README.md).

the first two items are authoring features, so they start to move Prism past
pure rendering. the rendering model itself stays 2D either way - see
[not planned](#not-planned).

## near future

### prefabs

today a scene object is a class you write and add by hand: `GameObject`
subclassed, then attached with `Scene2D.addRootChild(_:)` or `Collection.add(_:)`.
there is no way to define one object tree and stamp out copies of it.

the AXB asset format already has the idea - an `.ax` file opens with
`template Ship { ... }`, and polygons inherit it with
`polygon ImpulseCore : Ship { ... }` - so a prefab is the same thing one level
up: a named tree that can be instantiated many times, each instance carrying its
own state.

### particles as meshes

`ParticleSystem` is CPU-only and hands back `[ParticleVertex]`
(`buildVertices()`), a type no `Mesh` accepts. a game has to convert those
vertices itself and draw them through `Canvas2D` - CASCADE does exactly that,
one `context.triangle(...)` call per particle, per frame - which drops the UVs
and rules out a texture, a material or a blend mode.

the plan is for a particle system to own a `Mesh` with a `Surface`, so particles
become ordinary geometry: one submit instead of one call per particle, and real
materials on top.

### Metal / macOS

the device is created as a Vulkan device today: `GPUDevice.swift` sets
`SDL_PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN` and passes
`SDL_GPUVulkanOptions` with Vulkan 1.3 and `shaderDrawParameters`. the shaders
are compiled to SPIR-V 1.6 by `Scripts/build_shaders.py`. Metal needs a second
path:

- shaders for Metal - MSL, either compiled from Slang or converted from SPIR-V,
  which is what [SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross)
  does (RmlUI's own compiled shader blob comes from the same tool)
- device creation that asks for MSL rather than SPIR-V, and a feature list
  without the Vulkan-only entries
- a pass over the SDL3 GPU backend, which was written with a Metal path in mind
  but has never been exercised - see the README's platform note

### Axis

the language content is authored in, and the one behind `.ax` and `.axb` (see
[content and Axis](README.md#content-and-axis)). compiling `.ax` into the `.axb`
the framework reads is a separate project, not this package - so nothing in the
framework changes when Axis is released. it is not public yet, and it will be soon,
at which point the compiler and the language reference become available with it.

### shard packs

content ships as loose files in a bundle today. a `.shard` would be a VPK-style
container instead: an index of named entries followed by the payload bytes, so a
game ships one file rather than a directory tree.

a pack is a container, not a codec, so this is lossless by construction - the
payloads go in verbatim. `.axb` is already the same shape on a smaller scale: one
`AXIS` magic, a versioned header, then offsets into a single blob.

the format is not the hard part. three loaders reach for a filesystem path rather
than for bytes, and those are what moving into a pack would cost:

- audio clips - `Audio.loadAudio(from:)` calls `Wav_load(path)`
- audio streams - `Audio.streamAudio(from:)` calls `WavStream_load(path)`
- fonts - `UIContext.loadFont(filePath:)` reaches `Rml::LoadFontFace(path)`

all three already have an in-memory route in the vendored libraries: `Wav_loadMem`
and `WavStream_loadMem` in SoLoud's C API, and `LoadFontFace(Span<const byte>, ...)`
in RmlUI's C++ API, which `rmlui_bridge` does not wrap yet. streaming is the one
hard piece, since `WavStream_loadMem` wants the whole blob resident rather than a
byte range read straight out of the pack.

what a pack drops is filesystem metadata, and any name identity not stored
verbatim - case folding or Unicode normalisation would change how lookups behave -
so a packer has to keep names exact and stay deterministic, or the byte-exact
checks `make check` runs would see a diff on every rebuild.

`url(forResource:)` stays: it is public API, and an external game consumes it by
URL. the least-breaking shape is an optional overlay - the store checks a mounted
shard, then falls back to the bundle.

## already marked in the code

- **continuous particle emission** - `ParticleSystem` is "burst-only for now":
  there is no emission rate, so no steady stream.
- **frame-rate-independent particle drag** - the velocity decay factor is applied
  per frame rather than per second, so particle motion changes with frame rate.
  the code says so where it happens.

## deferred

- **Windows** - the README calls it planned but currently deferred. SDL3, SoLoud
  and RmlUI all support it; the open question is dependencies, since the system
  libraries are reached through pkg-config shims.

## not planned

- **3D rendering, and a separate sprite abstraction** - everything is triangles
  through one pipeline.
- **3D audio** - panning is the full extent of positioning.

not listed above are the gameplay systems the consuming game owns today:
physics, animation, tilemaps, save games. Prism ships none of them, and this
roadmap does not change that.
