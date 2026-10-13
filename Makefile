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
# Pinned here and in ci.yml (env.FLUTTER_VERSION); check-flutter refuses to run
# with any other version rather than warning. A different Flutter analyzes
# against different lints and formats differently, so a local pass against one
# proves nothing about CI with the other.
FLUTTER_VERSION ?= 3.47.2

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
	@echo "  gate-proof     tool/gate_proof.sh: the gate goes red on a bad fixture"
	@echo "  check-flutter  assert Flutter $(FLUTTER_VERSION) (also run by every gate-* target)"
	@echo ""
	@echo "Flutter is PINNED to $(FLUTTER_VERSION); resolved: $(FLUTTER)"

.PHONY: check-flutter
check-flutter:
	@set -eo pipefail; \
	if [ ! -x "$(FLUTTER)" ]; then \
		echo "flutter not found: looked on PATH and at $(HOME)/Developer/flutter/bin/flutter."; \
		echo "  make FLUTTER=/path/to/flutter/bin/flutter gate"; \
		exit 1; \
	fi; \
	have=$$("$(FLUTTER)" --version --machine 2>/dev/null | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p'); \
	if [ "$$have" != "$(FLUTTER_VERSION)" ]; then \
		echo "Flutter $$have at $(FLUTTER), but the gate is pinned to $(FLUTTER_VERSION)."; \
		echo "Different versions gate against different lints, so a local pass proves nothing."; \
		echo "Change the pin in BOTH the Makefile (FLUTTER_VERSION) and ci.yml (env.FLUTTER_VERSION), or switch SDKs."; \
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

# The proof calls `make gate-format` / `make gate-analyze` itself (not `make
# gate`, which would recurse here), so it is a bash script rather than a recipe.
.PHONY: gate-proof
gate-proof:
	@echo "==> gate mutation proof (tool/gate_proof.sh)"
	bash tool/gate_proof.sh
