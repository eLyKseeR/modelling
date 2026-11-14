# Run TLC on the models. The jar is in git LFS. Override: make TLA2TOOLS=/path/tla2tools.jar pos
# Parallel: make -j4 all WORKERS=1 (each run's output is printed in one piece when it ends).
TLA2TOOLS ?= $(CURDIR)/ext/tla2tools.jar
PLANTUML ?= $(CURDIR)/ext/plantuml.jar
WORKERS ?= 4
# TLC copies its standard modules (Naturals.tla, ...) to java.io.tmpdir and parses them from there.
# Parallel runs sharing one tmpdir read each other's half-written copies and fail at random (rc=150),
# so every run gets its own: $$tmp is set by the recipe below.
TLC = java -XX:+UseParallelGC -Djava.io.tmpdir="$$tmp" -cp "$(TLA2TOOLS)" tlc2.TLC -workers $(WORKERS)

# One target per cfg: pos/PoS_lost.cfg -> pos/PoS_lost.tlc (run alone: make pos/PoS_lost.tlc).
# The module is the cfg name up to the first "_" (EconPoS_lost.cfg checks EconPoS.tla).
# A cfg whose first line says "violation expected" is a negative test: it must end with a violation
# (TLC exit 12 invariant, 13 temporal) of the property it names, the first INVARIANTS entry (else a
# temporal property), so a broken spec cannot pass by violating TypeOK. Every other cfg must pass.
CFGS := $(wildcard pos/*.cfg econ/*.cfg)
RUNS := $(CFGS:.cfg=.tlc)
# *_big.cfg: same model at a larger size, minutes each; only in `make big`
BIG := $(filter %_big.tlc,$(RUNS))
DEF := $(filter-out $(BIG),$(RUNS))

.PHONY: all big uml-check diagrams pos econ econpos restore replicas sybil $(RUNS)
all: uml-check $(DEF)
big:      $(BIG)
pos:      $(filter pos/%,$(DEF))
econ:     $(filter econ/Econ.tlc econ/Econ_%,$(DEF))
econpos:  $(filter econ/EconPoS%,$(DEF))
restore:  $(filter econ/Restore%,$(DEF))
replicas: $(filter econ/Replicas%,$(DEF))
sybil:    $(filter econ/Sybil%,$(DEF))

$(RUNS): %.tlc: %.cfg
	@cd $(@D) && c=$(basename $(@F)) && m=$${c%%_*} && tmp=$$(mktemp -d) && trap 'rm -rf "$$tmp"' EXIT && \
	{ $(TLC) -metadir states/$$c -config $$c.cfg $$m.tla > $$tmp/log; rc=$$?; echo "== $$c"; cat $$tmp/log; \
	  if head -1 $$c.cfg | grep -q 'violation expected'; then \
	    test $$rc -ge 12 -a $$rc -le 13 || { echo "FAIL $$c: expected a violation, got rc=$$rc"; exit 1; }; \
	    want=$$(awk '/^INVARIANTS/ {print "Invariant " $$2 " is violated"; exit}' $$c.cfg); \
	    test -n "$$want" || want="Temporal properties were violated"; \
	    grep -q "$$want" $$tmp/log || { echo "FAIL $$c: expected: $$want"; exit 1; }; \
	  else test $$rc -eq 0 || { echo "FAIL $$c: must pass, got rc=$$rc"; exit 1; }; fi; }

# the committed per-config diagrams (uml/*.puml) must match the cfgs; needs python3
uml-check:
	python3 gen_uml.py --check

# regenerate the per-config PlantUML and render everything to out/<file>/<diagram>.png (jar: ext/plantuml.jar, git LFS)
diagrams:
	python3 gen_uml.py
	cd uml && for f in *.puml; do java -jar "$(PLANTUML)" -tpng -o "$$PWD/../out/$${f%.puml}" "$$f"; done
