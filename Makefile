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
# A target whose recipe fails or is interrupted is deleted, so a half-written
# file (the dictionary asset, WP3) never counts as built on the next run.
.DELETE_ON_ERROR:

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
	@echo "  gate           the merge gate == ci.yml: format, analyze, test, proof, build-ios"
	@echo "  gate-format    dart format --set-exit-if-changed, whole tree"
	@echo "  deps           flutter pub get in the app and in app/packages/ort_ffi"
	@echo "  gate-analyze   flutter analyze --fatal-infos"
	@echo "  gate-test      flutter test (app and app/packages/ort_ffi; fetches ORT for macOS and builds the models first)"
	@echo "  gate-proof     tool/gate_proof.sh: each gate-* target goes red on its bad fixture"
	@echo "  gate-build-ios flutter build ios (simulator debug + unsigned device release), nm proves ORT is linked"
	@echo "  ort-macos      fetch ONNX Runtime $(ORT_VERSION) for macOS into $(ORT_DIR) (sha256 pinned)"
	@echo "  ffigen         regenerate the ORT C API bindings in $(ORT_PKG) from the fetched headers"
	@echo "  check-flutter  assert Flutter $(FLUTTER_VERSION) (also run by every gate-* target)"
	@echo "  models         build the ONNX graphs into app/assets/models/ (wp0/build_graphs.py; creates wp0/.venv)"
	@echo "  models-check   run the built graphs against the synthetic goldens (wp0/check_goldens.py)"
	@echo "  dict           build app/assets/dict/dictionary.sqlite from the pinned JMdict/KANJIDIC2"
	@echo "                 releases (downloads once into tool/dict/downloads/); not part of gate"
	@echo "  gate-integration  integration_test/ on a booted iOS Simulator (NOT in gate, see below)"
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
# Ordered cheapest-first, so a formatting slip fails in seconds. The proof
# re-runs gate-format and gate-analyze on a mutated tree; the iOS build is
# last because it is the slowest (minutes) and depends on nothing above.
.PHONY: gate
gate: gate-format gate-analyze gate-test gate-proof gate-build-ios
	@echo ""
	@echo "✅ gate green (format, analyze, test, proof, build-ios)."

# Whole tree from the repo root: every .dart file git can see, not only app/,
# so a tool/ or script written in Dart later is gated without editing this.
# dart format skips hidden directories (.dart_tool, .git) on its own.
.PHONY: gate-format
gate-format: check-flutter
	@echo "==> dart format --set-exit-if-changed (whole tree)"
	"$(DART)" format --output=none --set-exit-if-changed .

# The app and the ort_ffi package are separate pub packages; the analyzer and
# the tests only see resolved imports when BOTH have been `pub get`. Without
# this the package's tool/ffigen.dart analyzes against unresolved types and
# fails --fatal-infos on a fresh checkout (found on the first gate on main
# after the WP2a merge: the branch's gate was green only because the agent had
# run pub get by hand).
.PHONY: deps
deps: check-flutter
	@set -eo pipefail; \
	echo "==> flutter pub get (app, app/packages/ort_ffi)"; \
	(cd $(APP) && "$(FLUTTER)" pub get); \
	(cd $(APP)/packages/ort_ffi && "$(FLUTTER)" pub get)

.PHONY: gate-analyze
gate-analyze: check-flutter deps
	@echo "==> flutter analyze --fatal-infos"
	cd $(APP) && "$(FLUTTER)" analyze --fatal-infos

# The app and the ort_ffi package are separate pub packages, so `flutter test`
# runs once in each; the package's tests load the real runtime from ORT_DIR
# and the app's golden tests run the built graphs from app/assets/models/
# (WP2b: the WP0b accuracy check is part of the gate, with its own step in
# the proof), so `models` is a prerequisite too.
.PHONY: gate-test
gate-test: check-flutter deps ort-macos models
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

# --- model graphs (WP0b, D6) --------------------------------------------------
#
# The weights never enter git; `make models` rebuilds app/assets/models/ from the
# pinned Python venv (uv + wp0/requirements.lock.txt). A prerequisite of
# gate-test since WP2b: the app's golden tests run the built graphs, and the
# proof's fourth step corrupts a golden to show the check is live. The build
# itself needs the network once (the manga-ocr and comic-text-detector weights).
PY_VENV := wp0/.venv
PY      := $(PY_VENV)/bin/python
MODELS_MANIFEST := app/assets/models/manifest.json

# uv is the only tool the model build needs that neither Flutter nor Xcode
# brings; CI provisions it with astral-sh/setup-uv, a Mac with `brew install uv`.
.PHONY: check-uv
check-uv:
	@if ! command -v uv >/dev/null 2>&1; then \
		echo "uv not found: 'make models' creates $(PY_VENV) with it."; \
		echo "  brew install uv   (CI: astral-sh/setup-uv, see ci.yml)"; \
		exit 1; \
	fi

.PHONY: models
models: check-uv
	@set -eo pipefail; \
	if [ ! -x "$(PY)" ]; then \
		echo "==> creating $(PY_VENV) (uv, Python 3.14, wp0/requirements.lock.txt)"; \
		uv venv --python 3.14 "$(PY_VENV)"; \
		uv pip install --python "$(PY)" -r wp0/requirements.lock.txt; \
	fi; \
	if [ "$(MODELS_MANIFEST)" -nt wp0/build_graphs.py ] && [ "$(MODELS_MANIFEST)" -nt wp0/requirements.lock.txt ]; then \
		echo "models up to date: $(MODELS_MANIFEST) is newer than wp0/build_graphs.py and wp0/requirements.lock.txt"; \
	else \
		echo "==> wp0/build_graphs.py"; \
		"$(PY)" wp0/build_graphs.py; \
	fi

.PHONY: models-check
models-check: models
	@set -eo pipefail; \
	echo "==> wp0/check_goldens.py"; \
	"$(PY)" wp0/check_goldens.py

# The first native dependency (onnxruntime-c, WP2) brings the iOS build into
# the gate (PLAN.md section 4.1): a debug simulator build and an unsigned
# release device build (no provisioning needed; it cannot be installed, only
# linked and stripped), and after each nm proves the ORT C API entry point is
# in the app binary, which is what dart:ffi looks up by name at run time; a
# build that silently dropped the static library, or a release strip that
# removed the symbol (Runner's STRIP_STYLE is non-global for that reason),
# would otherwise pass. Xcode 26 puts a debug build's code into
# Runner.debug.dylib next to a stub Runner, older Xcodes into Runner itself,
# so nm reads every Runner* file in the bundle. LANG: CocoaPods aborts on a
# non-UTF-8 locale. grep without -q, so nm is read to the end and pipefail
# cannot misfire.
IOS_SIM_APP    := $(APP)/build/ios/iphonesimulator/Runner.app
IOS_DEVICE_APP := $(APP)/build/ios/iphoneos/Runner.app
.PHONY: gate-build-ios
gate-build-ios: check-flutter
	@set -eo pipefail; \
	echo "==> flutter build ios --simulator --no-codesign"; \
	(cd $(APP) && LANG=en_US.UTF-8 "$(FLUTTER)" build ios --simulator --no-codesign); \
	echo "==> nm: OrtGetApiBase is linked into $(IOS_SIM_APP)/Runner*"; \
	find "$(IOS_SIM_APP)" -maxdepth 1 -type f -name 'Runner*' -exec nm -gU {} + | grep -F " T _OrtGetApiBase" >/dev/null; \
	echo "OrtGetApiBase linked (simulator, debug)"; \
	echo "==> flutter build ios --release --no-codesign"; \
	(cd $(APP) && LANG=en_US.UTF-8 "$(FLUTTER)" build ios --release --no-codesign); \
	echo "==> nm: OrtGetApiBase survives the release strip in $(IOS_DEVICE_APP)/Runner*"; \
	find "$(IOS_DEVICE_APP)" -maxdepth 1 -type f -name 'Runner*' -exec nm -gU {} + | grep -F " T _OrtGetApiBase" >/dev/null; \
	echo "OrtGetApiBase linked (device, release)"

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
# --- the dictionary asset (WP3) -----------------------------------------------
#
# Not part of the gate: the tests use the committed mini fixture. The asset is
# rebuilt when it is absent or when the script or the builder it calls changed.
# `flutter pub get` (not `dart pub get`) because tool/dict depends on the app
# package, which depends on the Flutter SDK; the script itself runs on dart.
DICT      := $(APP)/assets/dict/dictionary.sqlite
DICT_DEPS := tool/dict/build_dict.dart tool/dict/pubspec.yaml \
             $(APP)/lib/data/services/dictionary/dict_builder.dart \
             $(APP)/lib/data/services/dictionary/kana.dart \
             $(APP)/lib/domain/text/kana.dart

.PHONY: dict
dict: $(DICT)

$(DICT): $(DICT_DEPS) | check-flutter
	@set -eo pipefail; \
	cd tool/dict && "$(FLUTTER)" pub get >/dev/null && \
	"$(DART)" run build_dict.dart --out "$(abspath $(DICT))" --downloads "$(abspath tool/dict/downloads)"
# --- integration test (outside the gate) --------------------------------------
#
# Runs app/integration_test/ on the iOS Simulator with every port faked (WP4).
# NOT part of `make gate` / ci.yml yet: it needs Xcode, a booted simulator and
# a full iOS build (minutes, plus `pod install`), none of which the gate's
# macos-15 job sets up, and a simulator-only failure would block merges that
# `flutter test` already covers. `flutter analyze` in the gate still compiles
# the test, so it cannot rot silently. Promote it to the gate together with
# the first `flutter build ios` step (WP1 notes, "What will bite").
#
# The device is resolved by name; boot one with
#   xcrun simctl boot "iPhone 16"
# or pass a UDID: make INTEGRATION_DEVICE=<udid> gate-integration
INTEGRATION_DEVICE ?= iPhone 16

.PHONY: gate-integration
gate-integration: check-flutter
	@echo "==> flutter test integration_test on '$(INTEGRATION_DEVICE)'"
	cd $(APP) && "$(FLUTTER)" test integration_test -d "$(INTEGRATION_DEVICE)"
