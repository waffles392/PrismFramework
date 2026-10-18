# CRmlUiCore

Vendored [RmlUI](https://github.com/mikke89/RmlUi) - the HTML/CSS UI library Prism uses for UI.

- **Pinned version:** see `VERSION` (currently `6.3`, a released tag).
- **License:** RmlUI is MIT-licensed; see `LICENSE.txt`.

The tree is generated, never hand-edited:

```sh
Scripts/vendor_rmlui.py          # refresh from the pinned tag
Scripts/vendor_rmlui.py --check  # verify the tree matches the pin
```

## What is vendored

Only the parts the framework actually links:

- `Include/RmlUi/{Config,Core}` + `Include/RmlUi/Core.h` - public headers.
- `Source/Core/**` - the library sources, including the `Elements/`, `Layout/`
  and `FontEngineDefault/` subdirectories.

The optional `Debugger`, `Lua`, `SVG` and `Lottie` plugins, plus the upstream
`Samples`, `Tests`, `Backends` and CMake files, are intentionally excluded.

## How it is built

The `CRmlUiCore` target in `Package.swift` compiles every `Source/Core/**/*.cpp`
with the FreeType font engine:

- `-DRMLUI_STATIC_LIB`
- `-DRMLUI_FONT_ENGINE_FREETYPE`
- `-DRMLUI_VERSION="<pin>"`

RmlUI needs nothing generated at build time: its filter/shader compilation is a
virtual `RenderInterface` hook (`CompileFilter`/`CompileShader`) implemented by
the backend in `C/Sources/CRmlUI/src`. There is therefore no CMake or precompiled
archive involved.

The C bridge and SDL3-GPU backend that connect RmlUI to the framework live in the
sibling `C/Sources/CRmlUI` target.
