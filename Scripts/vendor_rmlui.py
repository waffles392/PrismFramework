#!/usr/bin/env python3

"""refresh the vendored RmlUI sources used by the 'CRmlUiCore' target, which is
declared in the root 'Package.swift' (see C/README.md)

RmlUI is pinned to a released tag and verified by SHA-256 so the tree can be
regenerated reproducibly on any machine with network access. only the parts
actually compiled into the engine are copied: the Core library (with the
FreeType font engine) and its public headers. samples, tests, backends and the
optional Debugger/Lua/SVG/Lottie plugins are intentionally left out.

usage:
  python3 Scripts/vendor_rmlui.py           # refresh C/Sources/CRmlUiCore
  python3 Scripts/vendor_rmlui.py --check   # verify the vendored tree matches the pin
"""

import filecmp
import hashlib
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.request

RMLUI_VERSION = '6.3'
RMLUI_SHA256 = 'd977298bb6147610e5984d5db85ddf284020d655a8713913f6982074f1dbdede'
RMLUI_URL = 'https://github.com/mikke89/RmlUi/archive/refs/tags/%s.tar.gz' % RMLUI_VERSION

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(REPO_ROOT, 'C', 'Sources', 'CRmlUiCore')

# 'XDG_CACHE_HOME' keeps the downloaded tarball out of the repo
CACHE_DIR = os.path.join(
    os.environ.get('XDG_CACHE_HOME', os.path.expanduser('~/.cache')),
    'prism',
    'rmlui',
)
TARBALL = os.path.join(CACHE_DIR, 'RmlUi-%s.tar.gz' % RMLUI_VERSION)

# the upstream trees that make up the vendored copy, as paths relative to the
# extracted tarball and to 'DEST'
PINNED_TREES = (
    os.path.join('Include', 'RmlUi', 'Config'),
    os.path.join('Include', 'RmlUi', 'Core'),
    os.path.join('Source', 'Core'),
)

# upstream files left out of the vendored copy
SKIP_NAMES = ('CMakeLists.txt',)


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
    print('downloading RmlUI %s ...' % RMLUI_VERSION)
    os.makedirs(CACHE_DIR, exist_ok=True)
    temporary = TARBALL + '.tmp'
    with urllib.request.urlopen(RMLUI_URL, timeout=120) as response:
        with open(temporary, 'wb') as handle:
            shutil.copyfileobj(response, handle)
    os.replace(temporary, TARBALL)


def copy_tree(from_dir, to_dir):
    """replace 'to_dir' with a copy of 'from_dir'"""
    shutil.rmtree(to_dir, ignore_errors=True)
    shutil.copytree(from_dir, to_dir)


def check(work):
    """compare the vendored files against a fresh extraction"""
    source = os.path.join(work, 'RmlUi-%s' % RMLUI_VERSION)
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

    if mismatch:
        return 1
    print('vendored RmlUI %s matches the pin' % RMLUI_VERSION)
    return 0


def vendor(work):
    """copy the pinned subset over 'DEST'"""
    source = os.path.join(work, 'RmlUi-%s' % RMLUI_VERSION)
    print('vendoring RmlUI %s into %s ...' % (
        RMLUI_VERSION,
        os.path.relpath(DEST, REPO_ROOT),
    ))

    os.makedirs(os.path.join(DEST, 'Include', 'RmlUi'), exist_ok=True)
    copy_tree(
        os.path.join(source, 'Include', 'RmlUi', 'Config'),
        os.path.join(DEST, 'Include', 'RmlUi', 'Config'),
    )
    copy_tree(
        os.path.join(source, 'Include', 'RmlUi', 'Core'),
        os.path.join(DEST, 'Include', 'RmlUi', 'Core'),
    )
    shutil.copyfile(
        os.path.join(source, 'Include', 'RmlUi', 'Core.h'),
        os.path.join(DEST, 'Include', 'RmlUi', 'Core.h'),
    )
    copy_tree(
        os.path.join(source, 'Source', 'Core'),
        os.path.join(DEST, 'Source', 'Core'),
    )
    shutil.copyfile(
        os.path.join(source, 'LICENSE.txt'),
        os.path.join(DEST, 'LICENSE.txt'),
    )

    # the upstream CMake project files are meaningless to the SwiftPM build
    for directory, _, names in os.walk(os.path.join(DEST, 'Source')):
        for name in names:
            if name in SKIP_NAMES:
                os.remove(os.path.join(directory, name))

    with open(os.path.join(DEST, 'VERSION'), 'w') as handle:
        handle.write('%s\n' % RMLUI_VERSION)

    print('done.')


def main():
    arguments = sys.argv[1:]
    check_only = '--check' in arguments

    unknown = [a for a in arguments if a != '--check']
    if unknown:
        sys.stderr.write("error: unknown argument '%s'\n" % unknown[0])
        return 2

    valid = sha256(TARBALL) == RMLUI_SHA256
    if not valid and check_only:
        sys.stderr.write(
            'error: cached tarball missing or checksum mismatch (%s)\n' % TARBALL
        )
        return 1

    if not check_only:
        if not valid:
            fetch()
        if sha256(TARBALL) != RMLUI_SHA256:
            sys.stderr.write(
                'error: SHA-256 mismatch for RmlUI %s tarball\n' % RMLUI_VERSION
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
