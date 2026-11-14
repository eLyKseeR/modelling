# CI image for the TLA+ model checks (.forgejo/workflows/tla.yml).
# node: the workflow actions (actions/checkout) run on node; the rest is what `make all` needs.
# The TLC jar is not in the image: it comes from git LFS (ext/tla2tools.jar).
#
# python3: gen_uml.py --check (make uml-check) keeps the committed diagrams in step with the cfgs.
#
# Built per architecture and combined into one multi-arch tag: see ci-image.sh.
FROM node:22-bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git git-lfs make python3-minimal default-jre-headless \
 && git lfs install --system \
 && rm -rf /var/lib/apt/lists/*
