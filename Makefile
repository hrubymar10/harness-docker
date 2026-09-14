#!make
MIN_MAKE_VERSION := 3.81

ifneq ($(MIN_MAKE_VERSION),$(firstword $(sort $(MAKE_VERSION) $(MIN_MAKE_VERSION))))
$(error GNU Make $(MIN_MAKE_VERSION) or higher required)
endif

SHELL := /bin/bash
export COMPOSE_PROJECT_NAME ?= harness-docker

.DEFAULT_GOAL := help

CONTAINER     ?= harness-docker
GIT_BRANCH    := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_SHA       := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

##@ Container

.PHONY: start stop restart status rebuild shell exec beeper-start beeper-stop vscode-wrapper

start: ## Build image and start container
	@bin/harness-docker-ctrl start

stop: ## Stop container
	@bin/harness-docker-ctrl stop

restart: stop start ## Restart container

status: ## Show container status
	@bin/harness-docker-ctrl status

rebuild: ## Refresh harnesses and restart using cached base layers
	@bin/harness-docker-ctrl rebuild

shell: ## Open a shell inside the container (auto-detects from host $$SHELL)
	@bin/harness-docker-ctrl shell

exec: ## Start an interactive harness session inside the container
	@bin/harness-docker-ctrl exec

beeper-start: ## Start host beeper server
	@bin/harness-docker-ctrl beeper-start

beeper-stop: ## Stop host beeper server
	@bin/harness-docker-ctrl beeper-stop

vscode-wrapper: ## Print path to the VS Code wrapper binary
	@printf '%s/bin/harness-docker-vscode-wrapper\n' "$$(pwd)"

##@ Testing

.PHONY: test test-verbose lint

test: ## Run host-side integration tests
	@echo "Running tests (branch: $(GIT_BRANCH), $(GIT_SHA))..."
	@shopt -s nullglob; tests=(test/test-*.sh); for test_file in "$${tests[@]}"; do bash "$$test_file" || { echo "FAILED: $$test_file" >&2; exit 1; }; done
	@cd docker-filter-proxy && go test ./...
	@cd beeper && go test ./...

test-verbose: ## Run tests with bash -x tracing
	@shopt -s nullglob; tests=(test/test-*.sh); for test_file in "$${tests[@]}"; do bash -x "$$test_file" || { echo "FAILED: $$test_file" >&2; exit 1; }; done

lint: ## Run shell syntax checks and shellcheck when available
	@files=(); while IFS= read -r -d '' file; do files+=("$$file"); done < <(find bin -type f ! -name '.*' -print0; find scripts -maxdepth 1 -type f -name '*.sh' -print0); \
	if (($${#files[@]})); then \
		bash -n "$${files[@]}"; \
		if command -v shellcheck >/dev/null 2>&1; then shellcheck "$${files[@]}"; fi; \
	fi

##@ Docker image

.PHONY: build-image

build-image: ## Build the Docker image without starting
	@bin/harness-docker-ctrl build-image

##@ Help

.PHONY: help

help: ## Display this help screen
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
