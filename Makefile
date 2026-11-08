# Rita test runner and skill-pack export. See tests/e2e/README.md for what
# each test does.
#
# Quick start:
#   make test-drift   # offline, deterministic — no model, no cost
#   make test-e2e     # model-driven plan generation — calls `claude -p`, costs tokens
#   make tests        # everything we have (drift + e2e)
#   make zip          # pack the committed skills into dist/rita-<rev>.zip
#
# Override the models the e2e test uses:
#   make test-e2e MODEL=sonnet GATE_MODEL=opus

SHELL := /usr/bin/env bash

# Optional model overrides for the model-driven e2e test.
MODEL ?=
GATE_MODEL ?=
E2E_ARGS := $(if $(MODEL),--model $(MODEL),) $(if $(GATE_MODEL),--gate-model $(GATE_MODEL),)

.DEFAULT_GOAL := help
.PHONY: tests test-drift test-e2e zip help

## tests: run every test we have (offline drift + model-driven e2e)
tests: test-drift test-e2e

## test-drift: offline, deterministic drift-detection test (no model, no cost)
test-drift:
	tests/e2e/test_drift.sh

## test-e2e: model-driven plan-generation test — calls `claude -p`, costs tokens
test-e2e:
	tests/e2e/test_claude.sh $(E2E_ARGS)

## zip: pack the three skills at HEAD into dist/rita-<rev>.zip (one skill pack)
# Built from `git archive HEAD`, so only committed files ship — untracked notes
# under docs/ can't leak in through the skills' docs/ symlinks.  The installer
# resolves those symlinks so each skill folder is self-contained.
zip:
	@set -eo pipefail; rev=$$(git describe --tags --always); out=dist/rita-$$rev.zip; \
	tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	mkdir -p "$$tmp/src" "$$tmp/home" "$$tmp/rita" dist; \
	git archive HEAD | tar -x -C "$$tmp/src"; \
	"$$tmp/src/install-claude-skills.sh" "$$tmp/home" >/dev/null; \
	mv "$$tmp/home/.claude/skills" "$$tmp/rita/skills"; \
	cp "$$tmp/src/LICENSE" "$$tmp/rita/"; \
	printf '# Rita\n\nThree related skills: rita-plan, rita-review, rita-delta.\nSource, docs and the latest version: https://github.com/malekseevdev/rita\n' > "$$tmp/rita/README.md"; \
	rm -f "$$out"; (cd "$$tmp" && zip -qr - rita) > "$$out"; \
	echo "Wrote $$out (from HEAD $$rev; uncommitted changes are not included)"

## help: list the available targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/## //'
