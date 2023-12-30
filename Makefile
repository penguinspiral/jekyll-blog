## -----------------------------------------------------------------------------
## This makefile serves as a "wrapper" interface to both Jekyll & MegaLinter
## standalone makefiles. This interface provides backwards compatability for
## previously configured SDLC stages by abstracting the underlying,
## namespaced "service" makefile.
##
## Target modifications to "service" makefiles must be reflected accordingly to
## this Makefile's TARGETS_${SERVICE} variable. "Service" makefile targets must
## be uniquely identifiable.
## ----------------------------------------------------------------------------

MAKE_OPTS       := --no-print-directory --makefile
MAKE_JEKYLL     := make $(MAKE_OPTS) Makefile.jekyll
MAKE_MEGALINTER := make $(MAKE_OPTS) Makefile.megalinter

TARGETS_JEKYLL     := deps build clean doctor serve
TARGETS_MEGALINTER := lint

.PHONY: $(TARGETS_JEKYLL) $(TARGETS_MEGALINTER) help

.DEFAULT_GOAL := help

$(TARGETS_JEKYLL): %:
	@$(MAKE_JEKYLL) $@ $(MAKEFLAGS)

$(TARGETS_MEGALINTER): %:
	@$(MAKE_MEGALINTER) $@ $(MAKEFLAGS)

help:
	@echo "=== Jekyll ==="
	@$(MAKE_JEKYLL) $@ $(MAKEFLAGS)
	@echo "\n=== Megalinter ==="
	@$(MAKE_MEGALINTER) $@ $(MAKEFLAGS)
