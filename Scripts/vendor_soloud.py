#!/usr/bin/env python3

"""refresh the vendored SoLoud sources used by the 'CSoloudCore' target, which
is declared in the root 'Package.swift' (see C/README.md)

SoLoud is pinned to a commit and verified by SHA-256 so the tree can be
regenerated reproducibly on any machine with network access. upstream tags are
from 2020 and predate several years of fixes, so the pin is a commit rather
than a release tag. only the parts actually compiled into the engine are
copied: the core mixer, the file decoders (WAV / MP3 / FLAC / OGG), the
miniaudio and null back-ends, the filters and the C API. demos, tools, glue,
docs and the other back-ends are intentionally left out.

the generated C API wraps every audio source SoLoud ships, including several
whose sources are not vendored (OpenMPT needs an external library; the chip
emulators and the speech synthesiser carry large data tables the engine has no
use for). those wrappers and their headers are pruned here as well, and the
pruned files say so at the top, as SoLoud's licence requires altered versions
to be plainly marked.

usage:
  python3 Scripts/vendor_soloud.py           # refresh C/Sources/CSoloudCore
  python3 Scripts/vendor_soloud.py --fetch   # download the pinned tarball into the cache
  python3 Scripts/vendor_soloud.py --check   # verify the vendored tree matches the pin
"""

import filecmp
import hashlib
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request

SOLOUD_COMMIT = 'e82fd32c1f62183922f08c14c814a02b58db1873'
SOLOUD_DATE = '2024-08-13'
SOLOUD_SHA256 = '863c5a2501ac935fb88bb357b1375e50d75876dd1f37806f4045143f46dbf3f1'
SOLOUD_URL = 'https://github.com/jarikomppa/soloud/archive/%s.tar.gz' % SOLOUD_COMMIT

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(REPO_ROOT, 'C', 'Sources', 'CSoloudCore')
SHIM = os.path.join(REPO_ROOT, 'C', 'Sources', 'CSoloud')

# SoLoud's generated C API header lives in the vendored tree, which is C++:
# whoever includes a header from there makes clang build that whole module, and
# it cannot be built as C. the header is plain C, so it is moved into the
# 'CSoloud' shim instead, where 'import CSoloud' sees it on its own.
API_HEADER = os.path.join('include', 'soloud_c.h')
SHIM_API_HEADER = os.path.join(SHIM, API_HEADER)

# 'XDG_CACHE_HOME' keeps the downloaded tarball out of the repo
CACHE_DIR = os.path.join(
    os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')),
    'prism',
    'soloud',
)
TARBALL = os.path.join(CACHE_DIR, 'soloud-%s.tar.gz' % SOLOUD_COMMIT)

# the upstream trees that make up the vendored copy, as paths relative to the
# extracted tarball and to 'DEST'
PINNED_TREES = (
    'include',
    os.path.join('src', 'core'),
    os.path.join('src', 'audiosource', 'wav'),
    os.path.join('src', 'audiosource', 'noise'),
    os.path.join('src', 'audiosource', 'sfxr'),
    os.path.join('src', 'backend', 'miniaudio'),
    os.path.join('src', 'backend', 'null'),
    os.path.join('src', 'c_api'),
    os.path.join('src', 'filter'),
)

# upstream files left out of the vendored copy
SKIP_NAMES = ('soloud.def',)

# audio sources that are not vendored, as (class, header) pairs. their wrappers
# are pruned from the generated C API and their headers from 'include'
PRUNED_FEATURES = (
    ('Ay', 'ay'),
    ('Monotone', 'monotone'),
    ('Openmpt', 'openmpt'),
    ('Speech', 'speech'),
    ('TedSid', 'tedsid'),
    ('Vic', 'vic'),
    ('Vizsn', 'vizsn'),
)

VERSION = '%s (%s)\n' % (SOLOUD_COMMIT, SOLOUD_DATE)

# stb_vorbis' own stream bounds test checks unsigned wrap-around, which clang
# diagnoses as '-Wtautological-compare'. silence it rather than touch the
# decoder's behaviour, so the engine still builds warning-free
STB_VORBIS_NOTE = """/* NOTE: modified for Prism by Scripts/vendor_soloud.py, to silence clang's
   '-Wtautological-compare' warning in the stream bounds test below. */
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wtautological-compare"
#endif

"""

README = """# CSoloudCore

Vendored [SoLoud](https://github.com/jarikomppa/soloud) at commit
`{commit}` ({date}), under the zlib/libpng licence (see `LICENSE.txt`).

Nothing here is edited by hand. Run `make vendor` (or
`python3 Scripts/vendor_soloud.py`) to regenerate the tree, and
`python3 Scripts/vendor_soloud.py --check` to verify it still matches the pin.
The engine only ever reaches this target through the `CSoloud` shim.

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
or speech data the engine does not use. Both files that are altered say so at
the top, as SoLoud's licence requires. `stb_vorbis.c` likewise carries a note
that silences one upstream warning, so the engine builds warning-free.

`include/soloud_c.h` is not vendored here either. It is plain C, but including
it from a C++ target makes clang try to build that whole target as C, which
cannot work, so the script moves it into the `CSoloud` shim
(`C/Sources/CSoloud/include/soloud_c.h`) where Swift can import it on its own.
""".format(commit=SOLOUD_COMMIT, date=SOLOUD_DATE)


def sha256(path):
    """hex digest of 'path', or 'None' when it cannot be read"""
    digest = hashlib.sha256()
    try:
        with open(path, 'rb') as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                digest.update(chunk)
    except OSError:
        return None
    return digest.hexdigest()


def leading_name(line):
    """the identifier a top-level declaration or definition starts with"""
    if not line[:1].isalpha() and line[:1] != '_':
        return None
    head = line.split('(', 1)
    if len(head) != 2:
        return None
    words = head[0].split()
    if not words:
        return None
    return words[-1].rstrip('*').strip()


def pruned_type(name):
    """is 'name' one of the audio sources this package does not vendor?"""
    return name.split('_')[0] in [feature for feature, _ in PRUNED_FEATURES]


def prune_includes(text):
    """drop the includes of the headers that were pruned"""
    unwanted = [
        '#include "../include/soloud_%s.h"' % header
        for _, header in PRUNED_FEATURES
    ]
    return '\n'.join(line for line in text.split('\n') if line.strip() not in unwanted)


def prune_definitions(text):
    """drop every function definition of a pruned audio source"""
    lines = text.split('\n')
    kept = []
    index = 0
    while index < len(lines):
        name = leading_name(lines[index])
        if name is None or not pruned_type(name):
            kept.append(lines[index])
            index += 1
            continue

        # the definition runs to the line that closes its brace
        depth = 0
        while index < len(lines):
            depth += lines[index].count('{') - lines[index].count('}')
            closed = depth == 0 and '}' in lines[index]
            declaration = depth == 0 and lines[index].rstrip().endswith(';')
            index += 1
            if closed or declaration:
                break
        while index < len(lines) and lines[index].strip() == '':
            index += 1
        kept.append('')

    return '\n'.join(kept)


def prune_declarations(text):
    """drop every declaration of a pruned audio source, and its type"""
    kept = []
    for line in text.split('\n'):
        name = leading_name(line)
        if name is not None and pruned_type(name):
            continue
        stripped = line.rstrip()
        if stripped.startswith('typedef void'):
            handle = stripped.rstrip(';').split()[-1]
            if handle in [feature for feature, _ in PRUNED_FEATURES]:
                continue
        kept.append(line)
    return '\n'.join(kept)


def prune_note():
    """the 'this is not upstream' banner the licence asks for"""
    features = ', '.join(feature for feature, _ in PRUNED_FEATURES)
    return (
        'NOTE: modified for Prism by Scripts/vendor_soloud.py. The generated\n'
        'wrappers for %s were removed,\n'
        'because those audio sources are not vendored.\n' % features
    )


def mark_cpp(text):
    """'text' with a C++ comment banner on top"""
    note = ''.join('// %s' % line for line in prune_note().splitlines(True))
    return '%s\n%s' % (note, text)


def mark_c(text):
    """'text' with a C comment banner on top"""
    note = '/* %s */\n' % prune_note().rstrip('\n')
    return '%s\n%s' % (note, text)


def pinned_files(root):
    """every pinned file under 'root', as paths relative to it"""
    found = []
    for tree in PINNED_TREES:
        for directory, _, names in os.walk(os.path.join(root, tree)):
            for name in names:
                if name in SKIP_NAMES:
                    continue
                found.append(os.path.relpath(os.path.join(directory, name), root))
    return sorted(found)


def same(first, second):
    """'true' when both paths exist and hold the same bytes"""
    if not os.path.isfile(first) or not os.path.isfile(second):
        return False
    return filecmp.cmp(first, second, shallow=False)


def extract(tarball, work):
    """unpack the tarball into 'work'"""
    with tarfile.open(tarball) as archive:
        if sys.version_info >= (3, 12):
            archive.extractall(work, filter='data')
        else:
            archive.extractall(work)


def fetch():
    """download the pinned tarball into the cache"""
    print('downloading SoLoud %s ...' % SOLOUD_COMMIT[:12])
    os.makedirs(CACHE_DIR, exist_ok=True)
    temporary = TARBALL + '.tmp'
    with urllib.request.urlopen(SOLOUD_URL, timeout=120) as response:
        with open(temporary, 'wb') as handle:
            shutil.copyfileobj(response, handle)
    os.replace(temporary, TARBALL)


def copy_tree(from_dir, to_dir):
    """replace 'to_dir' with a copy of 'from_dir'"""
    shutil.rmtree(to_dir, ignore_errors=True)
    shutil.copytree(from_dir, to_dir)


def read(path):
    with open(path) as handle:
        return handle.read()


def write(path, text):
    with open(path, 'w') as handle:
        handle.write(text)


def prepare(work):
    """extract and prune SoLoud, returning the tree to copy from and its C API"""
    source = os.path.join(work, 'soloud-%s' % SOLOUD_COMMIT)

    for _, header in PRUNED_FEATURES:
        os.remove(os.path.join(source, 'include', 'soloud_%s.h' % header))

    api = os.path.join(source, 'src', 'c_api', 'soloud_c.cpp')
    write(api, mark_cpp(prune_definitions(prune_includes(read(api)))))

    header = os.path.join(source, API_HEADER)
    text = mark_c(prune_declarations(read(header)))
    os.remove(header)

    decoder = os.path.join(source, 'src', 'audiosource', 'wav', 'stb_vorbis.c')
    write(decoder, STB_VORBIS_NOTE + read(decoder))

    return source, text


def check(work):
    """compare the vendored files against a fresh extraction"""
    source, api = prepare(work)
    upstream = pinned_files(source)
    vendored = pinned_files(DEST)

    mismatch = False
    for relative in upstream:
        if not same(os.path.join(source, relative), os.path.join(DEST, relative)):
            print('differs: %s' % relative)
            mismatch = True
    for relative in vendored:
        if relative not in upstream:
            print('extra: %s' % relative)
            mismatch = True

    if read(SHIM_API_HEADER) != api:
        print('differs: %s' % os.path.relpath(SHIM_API_HEADER, REPO_ROOT))
        mismatch = True

    if mismatch:
        return 1
    print('vendored SoLoud %s matches the pin' % SOLOUD_COMMIT[:12])
    return 0


def vendor(work):
    """copy the pinned subset over 'DEST'"""
    source, api = prepare(work)
    print('vendoring SoLoud %s into %s ...' % (
        SOLOUD_COMMIT[:12],
        os.path.relpath(DEST, REPO_ROOT),
    ))

    for tree in PINNED_TREES:
        copy_tree(
            os.path.join(source, tree),
            os.path.join(DEST, tree),
        )

    write(SHIM_API_HEADER, api)

    shutil.copyfile(
        os.path.join(source, 'LICENSE'),
        os.path.join(DEST, 'LICENSE.txt'),
    )

    # the upstream module-definition file is meaningless to the SwiftPM build
    for directory, _, names in os.walk(DEST):
        for name in names:
            if name in SKIP_NAMES:
                os.remove(os.path.join(directory, name))

    write(os.path.join(DEST, 'README.md'), README)
    write(os.path.join(DEST, 'VERSION'), VERSION)

    print('done.')


def main():
    arguments = sys.argv[1:]
    check_only = '--check' in arguments
    fetch_only = '--fetch' in arguments

    unknown = [a for a in arguments if a not in ('--check', '--fetch')]
    if unknown:
        sys.stderr.write("error: unknown argument '%s'\n" % unknown[0])
        return 2
    if check_only and fetch_only:
        sys.stderr.write("error: '--check' and '--fetch' are mutually exclusive\n")
        return 2

    valid = sha256(TARBALL) == SOLOUD_SHA256
    if fetch_only:
        if not valid:
            fetch()
        if sha256(TARBALL) != SOLOUD_SHA256:
            sys.stderr.write(
                'error: SHA-256 mismatch for SoLoud %s tarball\n' % SOLOUD_COMMIT[:12]
            )
            return 1
        return 0

    if not valid and check_only:
        sys.stderr.write(
            'error: cached tarball missing or checksum mismatch (%s)\n' % TARBALL
        )
        return 1

    if not check_only:
        if not valid:
            fetch()
        if sha256(TARBALL) != SOLOUD_SHA256:
            sys.stderr.write(
                'error: SHA-256 mismatch for SoLoud %s tarball\n' % SOLOUD_COMMIT[:12]
            )
            return 1

    with tempfile.TemporaryDirectory() as work:
        extract(TARBALL, work)
        if check_only:
            return check(work)
        vendor(work)
    return 0


if __name__ == '__main__':
    sys.exit(main())
