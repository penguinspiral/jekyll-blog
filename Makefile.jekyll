## -----------------------------------------------------------------------------
## This Makefile abstracts Jekyll commands suitable for local development, CI/CD
## pipelines, and release workflows.
## Its OS-agnostic, container-engine-agnostic (CRI) design facilitates
## consistent target naming regadless of its operating environment.
##
## To guarantee a consistent environment all Jekyll commands are performed
## within the context of the "defacto", glibc based official upstream Ruby
## container (https://hub.docker.com/_/ruby). Execution of Jekyll equivalent
## command targets outside this environment context are unsupported.
##
## Ruby gem caching (via 'bundler') is enabled across local development, CI/CD,
## pipelines, and release workflows to accelerate SDLC feedback.
##
## Supported container engines (CRI): podman, docker
## ----------------------------------------------------------------------------

# Enter interactive shell after target execution
INTERACTIVE ?= false

MAKEFILE_NAME := $(lastword $(MAKEFILE_LIST))

# Ruby gem management
BUNDLER_BINARY      := /usr/local/bin/bundler
BUNDLER_PRIMARY_CMD := cache

JEKYLL_BINARY     := /usr/local/bundle/bin/jekyll
JEKYLL_SERVE_OPTS ?= --host 0.0.0.0 \
                     --force_polling \
                     --incremental

# Baremetal environment detected, utilise container engine (CRI)
ifeq (,$(or $(wildcard /run/.containerenv),$(AWS_PLATFORM)))
    EXEC_ENV := _baremetal

    OCI_REGISTRY := docker.io/library
    OCI_IMG      := ruby
    OCI_SHA256   := c44f9bb8fedfac02c29cd7bb7e22779791b60296249c9e43dbffe85b153e795e  # 3.3.0-bookworm
    OCI_URI      := $(OCI_REGISTRY)/$(OCI_IMG)@sha256:$(OCI_SHA256)

    # Container engine (CRI) autodetect
    ifneq (,$(shell command -v podman 2>/dev/null))
        CRI_BINARY ?= podman
    endif

    ifneq (,$(shell command -v docker 2>/dev/null))
        CRI_BINARY ?= docker
    endif

    ifndef CRI_BINARY
        $(error "Error: Supported container engine binaries 'podman', 'docker' not found. Exiting.")
    endif

    # Container engine (CRI) agnostic defaults
    CRI_CMD  := run
    CRI_OPTS := --rm \
                --tty \
                --interactive \
                --publish 4000:4000 \
                --volume $(CURDIR):/srv/jekyll:rw \
                --workdir=/srv/jekyll

    ifeq ($(INTERACTIVE), true)
        INTERACTIVE_CMD := ; /bin/bash
    endif

    # Final CRI "passthrough" make command
    CRI_EXEC ?= /bin/bash -c 'make --makefile $(MAKEFILE_NAME) $(MAKECMDGOALS) $(MAKEFLAGS) $(INTERACTIVE_CMD)'

    # Prohibit unsupported "literal" execution of target & child recipe(s)
    # "Hacky" approach to 'no-op'ing context dependent binaries
    BUNDLER_BINARY := \# $(BUNDLER_BINARY)
    JEKYLL_BINARY  := \# $(JEKYLL_BINARY)
endif

.PHONY: _baremetal deps build clean doctor serve help

.DEFAULT_GOAL := help

_baremetal:        # Configures CRI environment (baremetal environments only)
	@echo "Baremetal platform detected! Leveraging '$(CRI_BINARY)' container engine..."
	$(CRI_BINARY) $(CRI_CMD) $(CRI_OPTS) $(OCI_URI) $(CRI_EXEC)
	@echo "Exiting '$(CRI_BINARY)' container engine! All parent recipes are no-op'd..."

deps: $(EXEC_ENV)  ## Manage Ruby gems installation & dependencies
	$(BUNDLER_BINARY) $(BUNDLER_PRIMARY_CMD)

build: deps        ## Build the site
	$(JEKYLL_BINARY) $@ $(JEKYLL_OPTS)

clean: deps        ## Clean the site (removes site output and metadata file) without building
	$(JEKYLL_BINARY) $@ $(JEKYLL_OPTS)

doctor: deps       ## Search site and print specific deprecation warnings
	$(JEKYLL_BINARY) $@ $(JEKYLL_OPTS)

serve: deps        ## Serve site locally (default TCP/4000)
	$(JEKYLL_BINARY) $@ $(JEKYLL_OPTS) $(JEKYLL_SERVE_OPTS)

help:              ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[32m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
