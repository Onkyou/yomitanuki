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

.PHONY: help
help:
	@echo "Targets:"
	@echo "  gate           the merge gate == ci.yml: format, analyze, test, proof"
	@echo "  gate-format    dart format --set-exit-if-changed, whole tree"
	@echo "  gate-analyze   flutter analyze --fatal-infos"
	@echo "  gate-test      flutter test"
	@echo "  gate-proof     tool/gate_proof.sh: each gate-* target goes red on its bad fixture"
	@echo "  check-flutter  assert Flutter $(FLUTTER_VERSION) (also run by every gate-* target)"
	@echo "  dict           build app/assets/dict/dictionary.sqlite from the pinned JMdict/KANJIDIC2"
	@echo "                 releases (downloads once into tool/dict/downloads/); not part of gate"
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

.PHONY: gate-test
gate-test: check-flutter
	@echo "==> flutter test"
	cd $(APP) && "$(FLUTTER)" test

# The proof calls `make gate-format` / `gate-analyze` / `gate-test` itself (not
# `make gate`, which would recurse here), so it is a bash script, not a recipe.
.PHONY: gate-proof
gate-proof: check-flutter
	@echo "==> gate mutation proof (tool/gate_proof.sh)"
	bash tool/gate_proof.sh

# --- the dictionary asset (WP3) -----------------------------------------------
#
# Not part of the gate: the tests use the committed mini fixture. The asset is
# rebuilt when it is absent or when the script or the builder it calls changed.
# `flutter pub get` (not `dart pub get`) because tool/dict depends on the app
# package, which depends on the Flutter SDK; the script itself runs on dart.
DICT      := $(APP)/assets/dict/dictionary.sqlite
DICT_DEPS := tool/dict/build_dict.dart tool/dict/pubspec.yaml \
             $(APP)/lib/data/services/dictionary/dict_builder.dart \
             $(APP)/lib/data/services/dictionary/kana.dart

.PHONY: dict
dict: $(DICT)

$(DICT): $(DICT_DEPS) | check-flutter
	@set -eo pipefail; \
	cd tool/dict && "$(FLUTTER)" pub get >/dev/null && \
	"$(DART)" run build_dict.dart --out "$(abspath $(DICT))" --downloads "$(abspath tool/dict/downloads)"
