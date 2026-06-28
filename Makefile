# Rita test runner. See tests/e2e/README.md for what each test does.
#
# Quick start:
#   make test-drift   # offline, deterministic — no model, no cost
#   make test-e2e     # model-driven plan generation — calls `claude -p`, costs tokens
#   make tests        # everything we have (drift + e2e)
#
# Override the models the e2e test uses:
#   make test-e2e MODEL=sonnet GATE_MODEL=opus

SHELL := /usr/bin/env bash

# Optional model overrides for the model-driven e2e test.
MODEL ?=
GATE_MODEL ?=
E2E_ARGS := $(if $(MODEL),--model $(MODEL),) $(if $(GATE_MODEL),--gate-model $(GATE_MODEL),)

.DEFAULT_GOAL := help
.PHONY: tests test-drift test-e2e help

## tests: run every test we have (offline drift + model-driven e2e)
tests: test-drift test-e2e

## test-drift: offline, deterministic drift-detection test (no model, no cost)
test-drift:
	tests/e2e/test_drift.sh

## test-e2e: model-driven plan-generation test — calls `claude -p`, costs tokens
test-e2e:
	tests/e2e/test_claude.sh $(E2E_ARGS)

## help: list the available targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -e 's/## //'
