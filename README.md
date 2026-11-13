# data modelling

This repository contains models of the processes and data relations in [eLyKseeR](https://github.com/eLyKseeR).

## [01 Data Store](./01-DataStore.md)

## [02 Assemblies](./02-Assemblies.md)

## [03 Snapshot](./03-Snapshot.md)

## [04 Assembly Cache](./04-AssemblyCache.md)

## [05 Processor](./05-Processor.md)

## [06 Distribution](./06-Distribution.md)

## Status

The model reflects [elykseer-ml](https://github.com/eLyKseeR) v0.10.3 including the move of the _Distribution_ into Rocq (commit f42b221, 2026-11-13). The _Snapshot_ is part of the model but still planned.

The diagrams are written in PlantUML (`relations.uml/`, `services.uml/`) and rendered to `out/<folder>/<file>/<diagram name>.png`:

```sh
cd services.uml   # or relations.uml
for f in *.puml; do java -jar plantuml.jar -tpng -o "$PWD/../out/services.uml/${f%.puml}" "$f"; done
```
