# TLA+ models

Models of the multi-party archive network (writer, storage provider, reader, broker).

| dir | contents |
|---|---|
| [`pos/`](./pos/README.md) | Proof of Storage: probe, reputation, period proof; lost/slow/dropping/facade SP, partition |
| [`econ/`](./econ/README.md) | payment and settlement (`Econ`), settlement on the PoS proof with stake and profit check (`EconPoS`), restore payment (`Restore`), re-replication (`Replicas`), sybils and privacy (`Sybil`) |
| `uml/`, `out/` | PlantUML sources and rendered diagrams: overall per model, and one per config (`make diagrams`) |

## Run

```sh
make all                # every config; passing configs must say "No error has been found", negative configs must violate a property
make -j4 all WORKERS=1  # the same, four TLC runs in parallel (faster)
make pos                # per model: pos, econ, econpos, restore, replicas, sybil (passing and negative configs)
make pos/PoS_lost.tlc   # one config
make big                # the *_big.cfg configs: same models at a larger size (minutes, not in `make all` or CI)
make uml-check          # fail if the committed uml/*_configs.puml differ from the cfgs (part of `make all`)
make diagrams           # regenerate uml/*_configs.puml and render all PlantUML to out/ (jar: ext/plantuml.jar, also git LFS)
```

Every `pos/*.cfg` and `econ/*.cfg` is run; there is no list to keep. The cfg name up to the first `_` names the module (`EconPoS_lost.cfg` checks `EconPoS.tla`). A cfg whose first line says `violation expected` is a negative test: it must violate the property it names (the first `INVARIANTS` entry), which shows the check is not vacuous.

Details, configs and findings are in the READMEs of the subdirs. Uses TLC 2.19 from `ext/tla2tools.jar` (stored with git LFS: `git lfs install` once, then clone/pull as usual). Override with `make TLA2TOOLS=/path/tla2tools.jar WORKERS=8 pos`. TLC state files go to `*/states/<cfg>/` (git-ignored).

## Toolbox

*File → Open Spec → Add New Spec…* and pick e.g. `pos/PoS.tla` or `econ/EconPoS.tla` (`econ/PoS.tla` is a symlink to `../pos/PoS.tla`). The `.cfg` files are not imported: create a model and copy the constants, invariants and properties from the `.cfg` (model values such as `None`, `c1` stay model values).

## CI

`.forgejo/workflows/tla.yml` runs `make all` on every pull request, and every push to `model`, that touches `tla+/` models, configs, the Makefile or the jar. It fails if a passing config fails, a negative config does not violate the property its cfg names (the first `INVARIANTS` entry), or the committed per-config diagrams are out of date. `gen_uml.py` also fails when a cfg is missing a constant, does not parse, or names a module without a diagram template. The rendered PNGs are not checked in CI (no PlantUML there): re-run `make diagrams` after a config change. The job runs in the image built from [`Dockerfile`](./Dockerfile) (node for the workflow actions, git, git-lfs, make, python3 for `make uml-check`, Java; the jar itself comes from LFS).

The image is multi-arch (amd64 and arm64) and is built by hand, not in CI (the runner containers have no docker): run `docker login code.sbclab.net`, then `ci-image.sh amd64` and `ci-image.sh arm64` (each pushes `tla-ci:<tag>-<arch>`; on a Mac the non-native one runs under emulation), then `ci-image.sh manifest` to combine them into `tla-ci:<tag>`.

Bump `TAG` in `ci-image.sh` and the image tag in `tla.yml` together when the Dockerfile changes.
