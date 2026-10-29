# make vendor   refresh the vendored SoLoud and RmlUI source (pinned revisions)
# make fetch    download the pinned vendor tarballs (no tree changes)
# make shaders  rebuild SPIR-V from the .slang sources
# make check    verify the vendored source and generated shaders are current
# make build    compile the package
# make test     run the test suite
# make run      launch a consuming game (override with SANDBOX=...)
# make clean    remove build products
#
# the .spv shaders are committed, so 'make build' works straight after cloning.
# run 'make shaders' (needs the Slang compiler, 'slangc') after editing a .slang
# source, and 'make check' to confirm the compiled output is in sync.
# RmlUI and SoLoud are compiled from vendored source by SwiftPM.
#
# 'vendor', 'fetch', 'shaders' and 'check' are Python 3 (standard library only).
# override the interpreter with 'make ... PYTHON=/path/to/python3'.

SWIFT ?= swift
PYTHON ?= python3

# a local game that consumes this package. override the location with
# 'make run SANDBOX=/path/to/game'.
SANDBOX ?= ../Sandbox

.PHONY: all vendor fetch shaders check build test benchmark benchmark-gpu run clean

all: build

vendor:
	$(PYTHON) Scripts/vendor_rmlui.py
	$(PYTHON) Scripts/vendor_soloud.py

fetch:
	$(PYTHON) Scripts/vendor_rmlui.py --fetch
	$(PYTHON) Scripts/vendor_soloud.py --fetch

shaders:
	$(PYTHON) Scripts/build_shaders.py

check: fetch
	$(PYTHON) Scripts/vendor_rmlui.py --check
	$(PYTHON) Scripts/vendor_soloud.py --check
	$(PYTHON) Scripts/build_shaders.py --check

build:
	$(SWIFT) build

test:
	$(SWIFT) test

# opens a real window and runs the safe benchmark set: AXB parsing, audio,
# CPU workloads, and a tiny GPU clear/present smoke test. every benchmark is
# conservative.
# plain 'test' skips these so CI and headless machines stay headless.
benchmark:
	PRISM_BENCHMARK=1 PRISM_BENCHMARK_GPU=0 \
		$(SWIFT) test --filter Benchmark

# adds the guarded GPU workloads: 640x360, vsync, ~30 frames, ~5k
# non-overlapping triangles, ~2k canvas primitives. still safe for an
# integrated GPU.
benchmark-gpu:
	PRISM_BENCHMARK=1 PRISM_BENCHMARK_GPU=1 \
		$(SWIFT) test --filter Benchmark

lint:
	$(SWIFT) format lint --recursive --configuration .swift-format Sources Tests

run:
	$(SWIFT) run --package-path $(SANDBOX) Sandbox

clean:
	$(SWIFT) package clean
