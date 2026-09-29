# SpellTuner release helper (wraps release.sh). Output lands in the TOP-LEVEL
# dist/, one folder per source and flavour: dist/main/tbc/SpellTuner,
# dist/main/forever/SpellTuner (+ its module folders), dist/<worktree>/... (T23).
#
#   make release                       pick the main checkout or a worktree
#   make release SRC=main              non-interactive; SRC = name or path
#   make release SRC=feedback-round-3
#   make install WOW_ADDONS=/path/to/Interface/AddOns [SRC=...] [FLAVOUR=tbc|forever]
#       one flavour into one client: FLAVOUR names it (--install-tbc / --install-forever);
#       without FLAVOUR release.sh detects it from the path (_classic_beta_ = forever,
#       _anniversary_ = tbc) and refuses a path it cannot tell
#   make list                          show sources, branches, versions
#   make clean                         remove the top-level dist/
#
# WOW_ADDONS may also come from the environment.

.RECIPEPREFIX := >
SRC ?=
FLAVOUR ?=
WOW_ADDONS ?=
RELEASE := ./release.sh
SRCARG = $(if $(SRC),--src "$(SRC)",--menu)
ROOT := $(patsubst %/.git,%,$(abspath $(shell git rev-parse --git-common-dir 2>/dev/null)))

.PHONY: release install list clean

release:
> @$(RELEASE) $(SRCARG)

INSTALLARG = $(if $(FLAVOUR),--install-$(FLAVOUR),--install)

install:
> @test -n "$(WOW_ADDONS)" || { echo "usage: make install WOW_ADDONS=/path/to/Interface/AddOns [SRC=name] [FLAVOUR=tbc|forever]"; exit 1; }
> @test -z "$(FLAVOUR)" || test "$(FLAVOUR)" = tbc || test "$(FLAVOUR)" = forever || { echo "FLAVOUR is tbc or forever, not $(FLAVOUR)"; exit 1; }
> @$(RELEASE) $(SRCARG) $(INSTALLARG) "$(WOW_ADDONS)"

list:
> @$(RELEASE) --list

clean:
> rm -rf "$(ROOT)/dist"
