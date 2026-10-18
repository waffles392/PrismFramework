#!/usr/bin/env python3

"""compile the Slang shader sources in Sources/Prism/Graphics/Shaders into SPIR-V.

the generated *.spv files are committed, so a plain 'swift build' needs neither
Slang nor a separate step. run this after changing a .slang source; 'make check'
fails when the committed .spv files are stale. output is written straight to the
final path, and files are left untouched when their bytes are unchanged.

usage:
  python3 Scripts/build_shaders.py           # rebuild changed shaders
  python3 Scripts/build_shaders.py --check   # fail if the .spv files are stale
"""

import filecmp
import os
import shutil
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADER_DIR = os.path.join(REPO_ROOT, 'Sources', 'Prism', 'Graphics', 'Shaders')
SLANGC = os.environ.get('SLANGC', 'slangc')

# 'source:entry:stage:output'
SHADERS = (
    'base.slang:vertexMain:vertex:base.vert.spv',
    'base.slang:fragmentMain:fragment:base.frag.spv',
    'fullscreen.slang:vertexMain:vertex:fullscreen.vert.spv',
    'bloom_extract.slang:fragmentMain:fragment:bloom_extract.frag.spv',
    'bloom_blur.slang:fragmentMain:fragment:bloom_blur.frag.spv',
    'present.slang:fragmentMain:fragment:present.frag.spv',
)


def same(first, second):
    """'true' when both paths exist and hold the same bytes"""
    if not os.path.isfile(first) or not os.path.isfile(second):
        return False
    return filecmp.cmp(first, second, shallow=False)


def main():
    arguments = sys.argv[1:]
    check_only = '--check' in arguments

    unknown = [a for a in arguments if a != '--check']
    if unknown:
        sys.stderr.write("error: unknown argument '%s'\n" % unknown[0])
        return 2

    if shutil.which(SLANGC) is None:
        sys.stderr.write(
            "error: '%s' not found in PATH (set SLANGC=... to override)\n" % SLANGC
        )
        return 1

    stale = False
    with tempfile.TemporaryDirectory() as work:
        for row in SHADERS:
            source, entry, stage, output = row.split(':')
            compiled = os.path.join(work, output)

            command = [
                SLANGC,
                os.path.join(SHADER_DIR, source),
                '-entry', entry,
                '-stage', stage,
                '-target', 'spirv',
                '-profile', 'spirv_1_6',
                '-o', compiled,
            ]
            if subprocess.run(command).returncode != 0:
                sys.stderr.write("error: '%s' failed on %s\n" % (SLANGC, source))
                return 1

            destination = os.path.join(SHADER_DIR, output)
            if same(compiled, destination):
                continue

            if check_only:
                sys.stderr.write(
                    'stale: %s (run python3 Scripts/build_shaders.py)\n' % output
                )
                stale = True
                continue

            shutil.copyfile(compiled, destination)
            print('updated: %s' % output)

    if check_only:
        if stale:
            return 1
        print('all shaders up to date')
    return 0


if __name__ == '__main__':
    sys.exit(main())
