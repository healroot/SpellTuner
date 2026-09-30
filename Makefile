# SpellTuner release helper (wraps release.sh). Output lands in the TOP-LEVEL
# dist/, one folder per source and flavour: dist/main/tbc/SpellTuner,
# dist/main/forever/SpellTuner (+ its module folders), dist/<worktree>/... (T23).
#
#   make check                         every suite, apicheck, textcheck (tools/check.sh)
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
# T57 (P13, review Q5): release and install run the check of the source they
# build first (that source's own tools/check.sh) and build nothing when it
# fails. NO_CHECK=1 skips it: make release SRC=main NO_CHECK=1.
#
# WOW_ADDONS may also come from the environment.

.RECIPEPREFIX := >
SRC ?=
FLAVOUR ?=
WOW_ADDONS ?=
NO_CHECK ?=
RELEASE := ./release.sh
CHECK := tools/check.sh
ROOT := $(patsubst %/.git,%,$(abspath $(shell git rev-parse --git-common-dir 2>/dev/null)))

# The source to build, as a path: SRC as given, else the menu (release.sh --list).
# Then that source's check, unless NO_CHECK is set.
define PICK_AND_CHECK
src="$(SRC)"; \
if [ -z "$$src" ]; then src="$$($(CHECK) --pick)" || exit 1; fi; \
if [ -z "$(NO_CHECK)" ]; then \
    $(CHECK) --tree "$$src" || { echo "make: the check failed for $$src - nothing built (NO_CHECK=1 builds anyway)"; exit 1; }; \
else echo "make: NO_CHECK set - building $$src unchecked"; fi
endef

.PHONY: check release install list clean

check:
> @$(CHECK)

release:
> @$(PICK_AND_CHECK); \
> $(RELEASE) --src "$$src"

INSTALLARG = $(if $(FLAVOUR),--install-$(FLAVOUR),--install)

install:
> @test -n "$(WOW_ADDONS)" || { echo "usage: make install WOW_ADDONS=/path/to/Interface/AddOns [SRC=name] [FLAVOUR=tbc|forever] [NO_CHECK=1]"; exit 1; }
> @test -z "$(FLAVOUR)" || test "$(FLAVOUR)" = tbc || test "$(FLAVOUR)" = forever || { echo "FLAVOUR is tbc or forever, not $(FLAVOUR)"; exit 1; }
> @$(PICK_AND_CHECK); \
> $(RELEASE) --src "$$src" $(INSTALLARG) "$(WOW_ADDONS)"

list:
> @$(RELEASE) --list

clean:
> rm -rf "$(ROOT)/dist"
