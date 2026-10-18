# CSoloudCore

Vendored [SoLoud](https://github.com/jarikomppa/soloud) at commit
`e82fd32c1f62183922f08c14c814a02b58db1873` (2024-08-13), under the zlib/libpng licence (see `LICENSE.txt`).

Nothing here is edited by hand. Run `make vendor` (or
`python3 Scripts/vendor_soloud.py`) to regenerate the tree, and
`python3 Scripts/vendor_soloud.py --check` to verify it still matches the pin.
The framework only ever reaches this target through the `CSoloud` shim.

## vendored

| upstream | why |
| --- | --- |
| `include/` | public headers for the C++ sources |
| `src/core/` | the mixer, buses, voices and faders |
| `src/audiosource/wav/` | `Wav` and `WavStream`, plus the dr_libs and stb_vorbis decoders (WAV, MP3, FLAC, OGG) |
| `src/audiosource/noise/` | the noise generator |
| `src/audiosource/sfxr/` | the sfxr sound effect generator |
| `src/backend/miniaudio/` | the default back-end (`-DWITH_MINIAUDIO`) |
| `src/backend/null/` | the silent back-end (`-DWITH_NULL`), used when there is no audio device |
| `src/c_api/` | the generated C API |
| `src/filter/` | every filter |

## pruned

The generated C API wraps every audio source upstream ships, so its wrappers
for Ay, Monotone, OpenMPT, Speech, TED-SID, VIC and Vizsn are removed
(`Scripts/vendor_soloud.py`), together with their headers. Their sources are
not vendored: OpenMPT needs an external library, and the rest carry emulators
or speech data the framework does not use. Both files that are altered say so at
the top, as SoLoud's licence requires. `stb_vorbis.c` likewise carries a note
that silences one upstream warning, so the framework builds warning-free.

`include/soloud_c.h` is not vendored here either. It is plain C, but including
it from a C++ target makes clang try to build that whole target as C, which
cannot work, so the script moves it into the `CSoloud` shim
(`C/Sources/CSoloud/include/soloud_c.h`) where Swift can import it on its own.
