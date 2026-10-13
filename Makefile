# The merge gate (PLAN.md section 4.1).
#
# `make gate` == the single job in .github/workflows/ci.yml, step for step, and
# the two are meant to be diffed: a gate that exists only in CI is found after a
# push, one that exists only locally gets skipped. Whole tree, no baseline,
# from commit one: a violation that reaches main is outside every later diff.
#
# SHELL SAFETY: macOS ships GNU Make 3.81, where .SHELLFLAGS does not exist (it
# parses as an ordinary variable and is silently ignored), so every multi-command
# recipe below opens with an explicit `set -eo pipefail;`.
.DEFAULT_GOAL := help
SHELL := /bin/bash
.NOTPARALLEL:

# --- toolchain pin ------------------------------------------------------------
#
# Pinned ONCE, in app/pubspec.yaml (environment.flutter). This Makefile and
# ci.yml both read it from there with the same sed, so there is no second copy
# to drift. `:=` so that an exported FLUTTER_VERSION in the environment (fvm,
# asdf, a CI env block) cannot silently re-pin the local gate; a deliberate
# `make FLUTTER_VERSION=x` on the command line still can. check-flutter refuses
# to run with any other version rather than warning: a different Flutter
# analyzes against different lints and formats differently, so a local pass
# against one proves nothing about CI with the other.
PIN_SED := s/^ *flutter: *"\{0,1\}\([0-9][0-9.]*\)"\{0,1\} *$$/\1/p
FLUTTER_VERSION := $(strip $(shell sed -n '$(PIN_SED)' app/pubspec.yaml))

# `flutter` from PATH, falling back to the SDK this Mac keeps in ~/Developer.
# `dart` is ALWAYS the one next to the resolved flutter, never a second SDK
# from PATH, so the formatter and the analyzer cannot come from different
# toolchains. Override with `make FLUTTER=/path/to/flutter gate`.
FLUTTER ?= $(or $(shell command -v flutter 2>/dev/null),$(HOME)/Developer/flutter/bin/flutter)
DART    := $(dir $(realpath $(FLUTTER)))dart

APP := app
ORT_PKG := $(APP)/packages/ort_ffi

# --- ONNX Runtime for macOS ----------------------------------------------------
#
# `flutter test` runs real inference on the Mac (WP2 task 0), so the official
# macOS release binary is fetched once into an ignored directory, with its
# sha256 pinned HERE and nowhere else (ci.yml calls `make ort-macos`, as the
# proof calls make, so the hash cannot drift between the two). The archive is
# downloaded data: it lands in its own directory, is verified before it is
# opened, and nothing in it is ever executed; only the dylib, the headers and
# the licence are copied out. The headers are also what `make ffigen` reads,
# so the bindings are generated from exactly the release that is linked.
# Only an arm64 archive exists for this release (no universal2).
ORT_VERSION       := 1.31.0
ORT_MACOS_ARCHIVE := onnxruntime-osx-arm64-$(ORT_VERSION).tgz
ORT_MACOS_SHA256  := 1031b36dd3bdaa8d976a6130d9cf2a05e9be320b93ae804f8427b91dc3432afc
ORT_MACOS_URL     := https://github.com/microsoft/onnxruntime/releases/download/v$(ORT_VERSION)/$(ORT_MACOS_ARCHIVE)
ORT_DIR           := $(ORT_PKG)/tool/ort
ORT_MACOS_DYLIB   := $(ORT_DIR)/lib/libonnxruntime.$(ORT_VERSION).dylib
ORT_HEADER        := $(ORT_DIR)/include/onnxruntime_c_api.h

.PHONY: help
help:
	@echo "Targets:"
	@echo "  gate           the merge gate == ci.yml: format, analyze, test, proof"
	@echo "  gate-format    dart format --set-exit-if-changed, whole tree"
	@echo "  gate-analyze   flutter analyze --fatal-infos"
	@echo "  gate-test      flutter test"
	@echo "  gate-proof     tool/gate_proof.sh: each gate-* target goes red on its bad fixture"
	@echo "  ort-macos      fetch ONNX Runtime $(ORT_VERSION) for macOS into $(ORT_DIR) (sha256 pinned)"
	@echo "  ffigen         regenerate the ORT C API bindings in $(ORT_PKG) from the fetched headers"
	@echo "  check-flutter  assert Flutter $(FLUTTER_VERSION) (also run by every gate-* target)"
	@echo ""
	@echo "Flutter is PINNED to $(FLUTTER_VERSION) (app/pubspec.yaml); resolved: $(FLUTTER)"

.PHONY: check-flutter
check-flutter:
	@set -eo pipefail; \
	if [ -z "$(FLUTTER_VERSION)" ]; then \
		echo "No Flutter pin found: app/pubspec.yaml needs an 'environment: flutter: \"x.y.z\"' line."; \
		exit 1; \
	fi; \
	if [ ! -x "$(FLUTTER)" ]; then \
		echo "flutter not found: looked on PATH and at $(HOME)/Developer/flutter/bin/flutter."; \
		echo "  make FLUTTER=/path/to/flutter/bin/flutter gate"; \
		exit 1; \
	fi; \
	have=$$("$(FLUTTER)" --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p'); \
	if [ "$$have" != "$(FLUTTER_VERSION)" ]; then \
		echo "Flutter $$have at $(FLUTTER), but the gate is pinned to $(FLUTTER_VERSION)."; \
		echo "Different versions gate against different lints, so a local pass proves nothing."; \
		echo "Change the pin in app/pubspec.yaml (environment.flutter), or switch SDKs."; \
		exit 1; \
	fi; \
	echo "flutter $$have ($(FLUTTER))"

# --- the merge gate -----------------------------------------------------------
#
# Ordered cheapest-first, so a formatting slip fails in seconds. The proof runs
# last because it re-runs gate-format and gate-analyze on a mutated tree.
.PHONY: gate
gate: gate-format gate-analyze gate-test gate-proof
	@echo ""
	@echo "✅ gate green (format, analyze, test, proof)."

# Whole tree from the repo root: every .dart file git can see, not only app/,
# so a tool/ or script written in Dart later is gated without editing this.
# dart format skips hidden directories (.dart_tool, .git) on its own.
.PHONY: gate-format
gate-format: check-flutter
	@echo "==> dart format --set-exit-if-changed (whole tree)"
	"$(DART)" format --output=none --set-exit-if-changed .

.PHONY: gate-analyze
gate-analyze: check-flutter
	@echo "==> flutter analyze --fatal-infos"
	cd $(APP) && "$(FLUTTER)" analyze --fatal-infos

# The app and the ort_ffi package are separate pub packages, so `flutter test`
# runs once in each; the package's tests load the real runtime from ORT_DIR.
.PHONY: gate-test
gate-test: check-flutter ort-macos
	@set -eo pipefail; \
	echo "==> flutter test (app)"; \
	cd $(APP) && "$(FLUTTER)" test; \
	echo "==> flutter test (app/packages/ort_ffi)"; \
	cd packages/ort_ffi && "$(FLUTTER)" test

# The proof calls `make gate-format` / `gate-analyze` / `gate-test` itself (not
# `make gate`, which would recurse here), so it is a bash script, not a recipe.
.PHONY: gate-proof
gate-proof: check-flutter
	@echo "==> gate mutation proof (tool/gate_proof.sh)"
	bash tool/gate_proof.sh

# --- ONNX Runtime binaries and bindings ----------------------------------------
.PHONY: ort-macos
ort-macos: $(ORT_MACOS_DYLIB) $(ORT_HEADER)

$(ORT_MACOS_DYLIB) $(ORT_HEADER):
	@set -eo pipefail; \
	echo "==> onnxruntime $(ORT_VERSION) for macOS -> $(ORT_DIR)"; \
	dl="$(ORT_DIR)/download"; \
	rm -rf "$$dl"; mkdir -p "$$dl"; \
	curl -fsSL --retry 3 -o "$$dl/$(ORT_MACOS_ARCHIVE)" "$(ORT_MACOS_URL)"; \
	echo "$(ORT_MACOS_SHA256)  $$dl/$(ORT_MACOS_ARCHIVE)" | shasum -a 256 -c -; \
	tar -xzf "$$dl/$(ORT_MACOS_ARCHIVE)" -C "$$dl"; \
	src="$$dl/onnxruntime-osx-arm64-$(ORT_VERSION)"; \
	rm -rf "$(ORT_DIR)/lib" "$(ORT_DIR)/include"; \
	mkdir -p "$(ORT_DIR)/lib"; \
	cp "$$src/lib/libonnxruntime.$(ORT_VERSION).dylib" "$(ORT_DIR)/lib/"; \
	cp -R "$$src/include" "$(ORT_DIR)/include"; \
	cp "$$src/LICENSE" "$(ORT_DIR)/LICENSE"; \
	rm -rf "$$dl"; \
	echo "onnxruntime $(ORT_VERSION): $(ORT_MACOS_DYLIB)"

# Regenerates lib/src/bindings/onnxruntime_c_api.g.dart from the fetched
# headers (tool/ffigen.dart holds the filter). The output is excluded from the
# package's analyzer but formatted here, because gate-format covers the tree.
.PHONY: ffigen
ffigen: check-flutter ort-macos
	@set -eo pipefail; \
	cd $(ORT_PKG) && "$(DART)" run tool/ffigen.dart && "$(DART)" format lib/src/bindings
