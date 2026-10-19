# make vendor   refresh the vendored SoLoud and RmlUI source (pinned revisions)
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
# 'vendor', 'shaders' and 'check' are Python 3 (standard library only). override
# the interpreter with 'make ... PYTHON=/path/to/python3'.

SWIFT ?= swift
PYTHON ?= python3

# a local game that consumes this package. override the location with
# 'make run SANDBOX=/path/to/game'.
SANDBOX ?= ../Sandbox

.PHONY: all vendor shaders check build test run clean

all: build

vendor:
	$(PYTHON) Scripts/vendor_rmlui.py
	$(PYTHON) Scripts/vendor_soloud.py

shaders:
	$(PYTHON) Scripts/build_shaders.py

check:
	$(PYTHON) Scripts/vendor_rmlui.py --check
	$(PYTHON) Scripts/vendor_soloud.py --check
	$(PYTHON) Scripts/build_shaders.py --check

build:
	$(SWIFT) build

test:
	$(SWIFT) test

lint:
	$(SWIFT) format lint --recursive --configuration .swift-format Sources Tests

run:
	$(SWIFT) run --package-path $(SANDBOX) Sandbox

clean:
	$(SWIFT) package clean
