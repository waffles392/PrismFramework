# Prism

a framework for making 2D games in Swift, on top of SDL3's GPU API.

everything is 2D and mesh-based: shapes are converted to triangles and go
through the same batched pipeline. it includes the renderer (device, resources,
**Canvas2D**, materials, post-processing) plus the parts every game needs:
input, audio, events, a scene layer, an optional RmlUI UI, and a fixed-timestep
loop.

- **Language:** Swift 6
- **Backend:** SDL3 GPU
- **Shaders:** written in [Slang](https://shader-slang.com), compiled to SPIR-V
- **License:** BSD 3-Clause, see [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

## Requirements

the framework links against a few system libraries. they are not vendored, so
install them first:

| dependency | used for | Debian / Ubuntu | Homebrew | vcpkg |
|---|---|---|---|---|
| SDL3 | window, input, GPU device | **libsdl3-dev** | **sdl3** | **sdl3** |
| SDL3_image | texture loading (UI) | **libsdl3-image-dev** | **sdl3_image** | **sdl3-image** |
| FreeType | font rasterisation | **libfreetype-dev** | **freetype** | **freetype** |
| Vulkan headers | GPU device features | **libvulkan-dev** | **vulkan-loader** | [**Vulkan SDK**](https://vulkan.lunarg.com) |

the shims in **C/Sources/** read **pkg-config** metadata, so every platform needs
a `pkg-config` executable and a `.pc` file per library. that is automatic on
Linux and macOS. on Windows, **Scripts/build.ps1** gets both from vcpkg and
writes the one `.pc` file vcpkg does not provide (Vulkan) - see
[Building on Windows](#building-on-windows).

Swift 6.2 or newer is required. RmlUI and SoLoud are vendored in-tree and
compiled from source, so they need no package manager. the scripts under
**Scripts/** are plain Python 3 (standard library only) and are only needed to
refresh the vendored sources or rebuild the shaders.

**Platforms:** developed and tested on Linux x86-64 with Vulkan 1.3. Windows x64
is supported too, through the MSVC toolchain - see
[Building on Windows](#building-on-windows). the device is currently created
with a mandatory Vulkan/SPIR-V configuration, so macOS/Metal is not supported
yet; the SDL3 GPU backend is written to allow a Metal path later, but none has
been added.

## Build & test

the compiled **.spv** shaders are committed, so a fresh clone builds and runs
as-is:

```sh
swift build
swift test
```

the **Makefile** in the repo runs the same commands:

```sh
make build  # swift build
make test   # swift test
make check  # verify the vendored sources + compiled SPIR-V are in sync
make run    # launch a consuming game (`SANDBOX=` to point elsewhere)
make clean  # remove build products
```

the shaders and the vendored sources each have their own target:

```sh
make shaders # compile .slang -> .spv (needs `slangc`)
make fetch   # download the pinned RmlUI and SoLoud tarballs into the cache
make vendor  # re-fetch the pinned RmlUI and SoLoud sources (SHA-256 verified)
```

**make shaders** is needed after editing a **.slang** source: the **.spv** files are
committed, along with the **.slang** sources that produce them, and **make check**
fails if they drift from their sources. checking a shader means compiling it, so
**make check** needs `slangc` as well, and both it and the Python interpreter are
overridable: **make check SLANGC=/path/to/slangc** or
**make check PYTHON=/path/to/python3**. **make check** compares the vendored
sources against the pinned upstream tarballs and downloads them into
`~/.cache/prism` first if they are missing; **make fetch** does only that
download. **make vendor** is only needed when refreshing a vendored source.

## Building on Windows

Swift on Windows uses the **MSVC** toolchain, so every library has to be built
for MSVC. install these once:

- [Swift 6.2 or newer for Windows](https://www.swift.org/install/windows/)
- **Visual Studio 2022** with the **Desktop development with C++** workload
- **Git for Windows** (only needed if the script has to fetch vcpkg)

then, from a normal PowerShell prompt in the repository:

```powershell
.\Scripts\build.ps1          # debug build
.\Scripts\build.ps1 -Test    # build and run the tests
```

`Scripts\build.cmd` runs the same script from `cmd.exe`.

the script does the setup that used to be manual:

- imports the Visual Studio x64 environment, so an "x64 Native Tools" prompt is
  not needed
- finds vcpkg through `VCPKG_ROOT` / `-VcpkgRoot` / the usual locations, and
  clones and bootstraps it into `.vcpkg/` if there is none
- installs the dependencies declared in **vcpkg.json** into `vcpkg_installed/`
  (SDL3 with Vulkan, SDL3_image with PNG/JPEG, FreeType, Vulkan headers and
  `pkgconf`)
- creates the `pkg-config.exe` name SwiftPM looks for from vcpkg's
  `pkgconf.exe`
- writes the Vulkan `.pc` file automatically, so the LunarG SDK is optional
- puts the vcpkg DLL directory on `PATH` for the build and test run
- runs `swift build`, plus `swift test` when `-Test` is passed

other options are `-Configuration release`, `-Clean` and `-NoBootstrap`.
`-NoBootstrap` fails instead of cloning vcpkg when none is found.

the libraries are linked dynamically. the script sets `PATH` for its own run;
to launch an executable afterwards, add `vcpkg_installed\x64-windows\bin` to
`PATH` or copy the DLLs next to it.

**vcpkg.json** is also usable directly with `vcpkg install --triplet
x64-windows`, but the script remains the supported path: it handles the MSVC
environment and the `pkg-config` naming trap for you.

the **Makefile** is Unix-flavoured; on Windows use `Scripts\build.ps1` or plain
`swift build` from a developer prompt. the Python scripts work from any shell.

## Using Prism in another package

there are no external package dependencies, so Prism is consumed by URL:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/waffles392/PrismFramework.git", exact: "26.10.21"),
],
targets: [
    .target(name: "MyGame", dependencies: [
        .product(name: "Prism", package: "PrismFramework"),
    ]),
]
```

the compiled shaders are committed, so a checkout pulled in this way needs
neither Slang nor a separate build step.

releases are tagged with [CalVer](https://calver.org) as **YY.MM.DD**, e.g.
**26.10.18**. only the **Prism** product is public; every module is re-exported
through it, so **import Prism** is all you need.

## Repository layout

```
PrismFramework/
├── Package.swift          # single package manifest (Swift and C targets)
├── Sources/Prism/         # the framework itself
│   ├── Math/  Input/  Time/  Window/  Audio/
│   ├── Graphics/          # device, resources, Canvas2D, materials, post-processing
│   ├── Events/  Scene/  UI/  Core/
│   └── Exports.swift      # the one public product: 'import Prism'
├── C/Sources/             # all non-Swift code (see C/README.md)
│   ├── CSDL3/ CSDL3Image/ CFreetype/ CVulkan/  # pkg-config shims over the system libraries
│   ├── CRmlUI/ CSoloud/              # Prism's bridges to RmlUI and SoLoud
│   ├── CRmlUiCore/                   # vendored RmlUI 6.3 (see 'make vendor')
│   └── CSoloudCore/                  # vendored SoLoud (see 'make vendor')
├── Tests/PrismTests/
├── Scripts/               # vendor_rmlui.py, vendor_soloud.py, build_shaders.py,
│                          # build.ps1 / build.cmd (Windows)
├── Tools/dump_axb.py      # shows the content of .axb files
├── Makefile
├── vcpkg.json             # Windows dependencies (used by Scripts/build.ps1)
├── ROADMAP.md             # what is planned next
└── THIRD_PARTY_NOTICES.md
```

the C targets live under **C/Sources/** but are declared in the root
**Package.swift**. that is deliberate: SwiftPM does not allow a package consumed
by URL to have a local **path:** package dependency, so the C code has to be part
of this package for **.package(url:exact:)** to work. see
[C/README.md](C/README.md).

## Modules

| module | responsibility |
|---|---|
| Math | vectors, angles, collision check, interpolation |
| Time | fixed-timestep clock |
| Window | SDL3 window and event pump |
| Input | keyboard / mouse / gamepad actions and axes |
| Events | event dispatcher |
| Audio | sound loading, streaming, playback, filters and mixes |
| Graphics | GPU device, resources, **Canvas2D**, materials, post-processing |
| Scene | scene graph and entities |
| UI | optional RmlUI HTML/CSS layer |
| Core | framework wiring and the public entry point |

## Rendering model

a frame flows **Renderer** > **Frame** > **RenderEncoder**:

- **GPUDevice** owns the SDL3 GPU device and every resource created through it,
  releasing them before the device is destroyed.
- a frame acquires a command buffer and swapchain texture, draws into an
  offscreen HDR target, runs post-processing, and presents.
- **Surface** (shader + uniforms + blend mode + topology) and **Mesh** (vertex /
  index buffers + **Surface** + textures) form the reusable material and geometry
  layer. pipelines are cached per target format.
- **Canvas2D** is the immediate-mode drawing surface - paths, primitives,
  transforms and clipping are recorded into CPU-side batches and flushed as
  **Meshes**, preserving painter's order.

everything is triangles through one pipeline: there is no 3D path and no
separate sprite abstraction. game-specific rendering belongs in your game, not
in **Graphics**.

see [**C/README.md**](C/README.md) for what is hand-written, vendored or generated
in the C sources.

## Content and Axis

game content is authored in **Axis**, a language of its own: `.ax` files hold the
uncompiled source, and the Axis compiler turns them into `.axb`, the compiled
form the framework reads.

an `.axb` file is a small binary container. it opens with an `AXIS` magic and
carries its own version, and holds named polygon records. each record keeps the
name, the template it inherits from and its typed fields, so the compiled file
has the same shape as the source that produced it:

```
$ python3 Tools/dump_axb.py Tests/PrismTests/Resources/assets/mesh.axb
File size: 115 bytes (0x73)
Header: Version 1.0, Flags: 0
Sections: Metadata offset 32 (0 bytes), Polygon offset 32 (83 bytes)
...
Polygon Shape : Ground {
  array<vector> vertices[0] = [[1.2, 1.0], [1.0, 1.0], [0.0, -1.8]];
  vector bounds = [0.0, 0.0, 336.0, 166.399994];
}
```

the framework only reads `.axb`. **loadAXB(named:subdirectory:)** parses one and
caches the result, returning an **AXBFile** whose **mesh** is indexed by polygon
name; a malformed file reports the byte offset that broke it rather than failing
vaguely. the compiler is not part of this repo.

**Axis is not public yet - it will be soon.** until then only its output is in
the open, through the compiled `.axb` the framework loads.

the `.axb` readers in Prism will not change until Axis is public.

## Audio

**Audio** wraps [SoLoud](https://github.com/jarikomppa/soloud), vendored under
**C/Sources/CSoloudCore/** - see [C/README.md](C/README.md).
**loadAudio(from:)** decodes WAV, MP3, FLAC or OGG into memory, and
**streamAudio(from:)** reads the same formats from disk as they play. **play**
starts a voice and returns it, so a sound's volume, pan, speed and position can
be changed while it is playing, and voices are polyphonic: a new call never cuts
off the one before it.

three things sit on top of that:

- **filters** - **AudioEchoFilter**, **AudioReverbFilter**,
  **AudioEqualizerFilter** and the rest are loaded onto the framework
  (**addGlobalFilter**), onto a source (**setFilter**) or onto a bus. A filter is
  configured when it is created, and a loaded one is automated through the voice
  playing it.
- **buses** - **makeBus()** returns a voice of its own that others are played
  through, so music, effects and interface sounds can be faded, filtered and
  stopped separately.
- **generators** - **makeSfxr(preset:)** and **makeNoise()** produce sound with
  no asset at all.

there is no 3D audio: panning is the full extent of positioning. **Audio** also
needs no audio device - when there is none it starts a silent mixer and
**isSilent** says so, which is what keeps the test suite headless.

## Status

the 2D renderer and the framework modules are implemented and in use by a game
that consumes this package. GPU runtime verification needs a machine with a
working Vulkan 1.3 device; the test suite runs headless. see
[ROADMAP.md](ROADMAP.md) for what is planned next.

## Provenance

Prism contains code written by AI language models. some of it was written by
hand instead - the two are not distinguished file by file, and the AI-written
parts were reviewed, run and edited by hand before they landed.

[LICENSE](LICENSE) covers the repository as a whole; the third-party code named
in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) keeps its own terms.
