# Third-Party Notices

Prism uses the BSD 3-Clause License - see [LICENSE](LICENSE).

some code in this repo belongs to other projects. their licenses still apply to
their own code, not to Prism as a whole. each section below covers one project:
the ones whose code is copied into the repo, and the libraries you install
yourself.

---

## RmlUI 6.3 - MIT license

[RmlUI](https://github.com/mikke89/RmlUi) is the library that draws the optional
HTML/CSS UI. it shows up in the repo in two places.

### 1. the whole RmlUI core - `C/Sources/CRmlUiCore/`

this is RmlUI's `Source/Core` and `Include/RmlUi/{Config,Core}`, copied exactly
from version 6.3. you can download it again with `Scripts/vendor_rmlui.py`,
which checks the file with SHA-256 so you always get the same version. don't
edit these files by hand. RmlUI's license is saved next to them at
`C/Sources/CRmlUiCore/LICENSE.txt`.

### 2. the SDL3 GPU backend - `C/Sources/CRmlUI/src/`

these files come from RmlUI's `Backends/` folder, with tiny changes:

| file | came from | changes |
|---|---|---|
| `RmlUi_Renderer_SDL_GPU.cpp` | `Backends/RmlUi_Renderer_SDL_GPU.cpp` | none - just a comment saying where it came from |
| `RmlUi_Renderer_SDL_GPU.h` | `Backends/RmlUi_Renderer_SDL_GPU.h` | none - just that comment |
| `RmlUi_SDL_GPU/ShadersCompiledSPV.h` | `Backends/RmlUi_SDL_GPU/ShadersCompiledSPV.h` | none (this file is generated) |
| `RmlUi_Platform_SDL.cpp` | `Backends/RmlUi_Platform_SDL.cpp` | took out some SDL_Renderer code |
| `RmlUi_Platform_SDL.h` | `Backends/RmlUi_Platform_SDL.h` | took out a comment |

`rmlui_bridge.cpp` and `rmlui_bridge.h` are Prism's own code, covered by the
BSD 3-Clause License.

### code RmlUI itself carries

RmlUI's core pulls in two third-party containers of its own unless
`RMLUI_NO_THIRDPARTY_CONTAINERS` is defined, and Prism does not define it:

| library | license | what it does |
|---|---|---|
| robin_hood | MIT | `Containers/robin_hood.h` - the hash map and set |
| itlib | MIT | `Containers/itlib/` - the flat map and set |

both license texts are saved next to them, in
`C/Sources/CRmlUiCore/Include/RmlUi/Core/Containers/LICENSE.txt`, which
`Scripts/vendor_rmlui.py` copies along with the rest of RmlUI.

### the MIT license text

```
Copyright (c) 2008-2014 CodePoint Ltd, Shift Technology Ltd, and contributors
Copyright (c) 2019-2026 The RmlUi Team, and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### about the shader file

`C/Sources/CRmlUI/src/RmlUi_SDL_GPU/ShadersCompiledSPV.h` is generated, not
written by hand. it's the very same file RmlUI ships. RmlUI makes it with
`Backends/RmlUi_SDL_GPU/compile_shaders.py`, which needs
[SDL_shadercross](https://github.com/libsdl-org/SDL_shadercross). the generator
isn't included here because this file never changes.

---

## SoLoud - zlib/libpng license

[SoLoud](https://github.com/jarikomppa/soloud) is the audio engine behind
`Audio`. the parts Prism compiles are copied into `C/Sources/CSoloudCore/`,
pinned to commit `e82fd32c1f62183922f08c14c814a02b58db1873` (2024-08-13). you can
download them again with `Scripts/vendor_soloud.py`, which checks the tarball
with SHA-256 so you always get the same version. don't edit these files by hand.
SoLoud's license is saved next to them at `C/Sources/CSoloudCore/LICENSE.txt`.

### what the vendor script changes

SoLoud's license asks altered versions to be plainly marked, so the script says
what it changed at the top of each file it touches:

| file | change |
|---|---|
| `include/soloud_c.h`, `src/c_api/soloud_c.cpp` | the wrappers for Ay, Monotone, OpenMPT, Speech, TED-SID, VIC and Vizsn are removed, along with their headers, because those sources are not vendored - OpenMPT needs a library Prism does not carry, and the rest are chip emulators and a speech synthesiser the framework has no use for |
| `src/audiosource/wav/stb_vorbis.c` | one `#pragma` that silences a warning clang raises on an upstream bounds check; the code itself is untouched |

`soloud_c.h` is written into `C/Sources/CSoloud/` rather than left in the vendored
tree, because Swift can only import a C header from a target that is not C++. the
script writes both that header and the trimmed `soloud_c.cpp`, so they cannot
drift apart.

`C/Sources/CSoloud/soloud_bridge.cpp` and `soloud_bridge.h` are Prism's own code,
covered by the BSD 3-Clause License. they add the EQ filter and uniform filter
introspection, which SoLoud's C API does not generate.

### code SoLoud itself carries

the vendored tree includes the decoders and the device back-end SoLoud bundles.
SoLoud's own license file notes that these are all extremely liberal and need no
attribution in binary form:

| library | license | what it does |
|---|---|---|
| dr_libs (`dr_wav.h`, `dr_mp3.h`, `dr_flac.h`) | public domain / MIT-0 | WAV, MP3 and FLAC decoding |
| stb_vorbis | public domain / MIT | OGG Vorbis decoding |
| miniaudio | public domain / MIT-0 | the audio device back-end |

### the zlib/libpng license text

```
SoLoud audio engine
Copyright (c) 2013-2018 Jari Komppa

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

   1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.

   2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.

   3. This notice may not be removed or altered from any source
   distribution.
```

---

## libraries you install yourself

Prism uses these when you build it. none of their code is in this repo, so they
don't change Prism's license. if you give someone a finished program, check each
license yourself.

| library | license | what it does |
|---|---|---|
| SDL3 / SDL3_image | zlib | windows, input, GPU, images |
| FreeType | FTL or GPLv2 | draws text (used by RmlUI) |
| Vulkan headers | Apache-2.0 or MIT | struct and enum definitions for the GPU feature list; no Vulkan code is compiled in |
| Slang | see their repo | turns `.slang` into SPIR-V, only for `make shaders` |
