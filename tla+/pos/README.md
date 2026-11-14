# pos: Proof of Storage

`PoS.tla` models how the broker checks that a storage provider (SP) keeps a chunk. The SP is the only actor that may misbehave. The result of a period is a boolean `proof`; the economic models in [`../econ`](../econ/README.md) pay or refund on it.

![PoS sequence](../out/pos/PoS%20sequence.png)

## What is modelled

* **Probe**: the broker sends a challenge (chunk, byte range, fresh nonce); the SP answers with the HMAC of that range; the broker compares it with the HMAC on its reference copy. The HMAC is abstract: only a holder of the chunk can compute it.
* **Time** is discrete and passes only while the broker waits. An answer counts if it arrives within `Budget` ticks; otherwise `Timeout`. An SP holding the chunk answers within `MaxLat` ticks.
* **Reputation**: every probe gives a sample (100 = correct and in time, else 0), folded into an integer EMA `rep' = (rep*(W-1)+sample) div W`.
* **Period and proof**: the broker probes (chunks not yet answered first) until nonces or time are used up, then `proof = rep >= Thr /\ probes >= MinProbes /\ every chunk answered`.
* **Deviations of the SP**, each switched by a constant:

| deviation | constants | what happens |
|---|---|---|
| lost chunk | `HeldInit` smaller than `Chunks` | cannot answer for it |
| slow SP | `MaxLat > Budget` | every answer is late |
| `DropChunk` | `AllowDrop` | deletes a chunk at any time |
| `Facade` | `Other`, `RelayLat` | answers for a chunk it lacks by fetching it from another provider |
| partition | `PartLen` | unreachable for `PartLen` ticks (once) |

![PoS period](../out/pos/PoS%20period.png)

## Properties

| name | kind | meaning |
|---|---|---|
| `TypeOK` | invariant | types |
| `NoFalseProof` | invariant | a relayed (facade) answer is never accepted |
| `ProofSound` | invariant | a proof means every chunk was answered, by a holder of the data |
| `RepAboveThreshold` | invariant | the reputation stays above `Thr` |
| `HonestGetsProof` | invariant | an honest, fast, reachable SP always gets the proof |
| `NoProof` | invariant | an SP lacking a chunk never gets the proof |
| `Resolved`, `Closes` | liveness | every probe ends; the period ends |

## Configurations

`make pos` runs the configs that must pass and those that must violate a property (negative tests, "violation expected" in their first line: they show the check is not vacuous). Diagram per config: [`../out/pos_configs`](../out/pos_configs/overview.png).

| config | SP behaviour | result |
|---|---|---|
| `PoS` | honest, fast | all hold |
| `PoS_lost_live` | lost chunk | no proof, probes still end |
| `PoS_facade` | relay slower than the deadline | no proof |
| `PoS_drop_live` | drops chunks at any time | proofs stay sound |
| `PoS_part_ok` | partition of 2 ticks | honest SP still gets the proof |
| `PoS_lost` | lost chunk | `HonestGetsProof` violated |
| `PoS_slow` | slower than the deadline | `HonestGetsProof` violated |
| `PoS_drop` | drops a chunk | `RepAboveThreshold` violated |
| `PoS_facade_bad` | relay within the deadline | `NoProof` violated: the facade gets a proof |
| `PoS_part_long` | partition of 4 ticks | `HonestGetsProof` violated |
| `PoS_partial` | keeps one of two byte ranges per chunk | `NoProof` violated: probes on the kept half give a proof |
| `PoS_big` | as `PoS`, 3 chunks, 5 nonces (`make big`) | all hold |
| `PoS_part_ok_big` | as `PoS_part_ok`, 3 chunks, 5 nonces (`make big`) | honest SP still gets the proof |

![configs](../out/pos_configs/overview.png)

## Findings

* A facade is caught only while `MaxLat <= Budget < RelayLat`: the deadline must sit between an honest SP's latency and the cost of relaying. That gap is the design limit of any latency SLA.
* Coverage-first probing makes a lost chunk always visible; a random probe could miss it.
* Chunk-level coverage is not enough: an SP keeping part of every chunk gets the proof when the probes hit the kept ranges (`PoS_partial`). Certainty needs `|Chunks| x |Ranges|` probes per period; fewer only catch it with some probability per period (not modelled).
* A chunk dropped *after* its last probe still counts: the proof states the past period only.
* A short partition is absorbed by the spare probes (`Nonces` beyond the number of chunks); a long one costs the honest SP its proof. The SLA a broker can offer is therefore "outages up to about `PartLen` ticks per period". This needs one failed probe to keep the reputation at or above the threshold, `100 x (W - 1) / W >= Thr`: `PoS_part_ok` passes at `Thr = 75` (100 -> 75) and fails at `Thr = 76`.

Not modelled: several SPs per chunk, real HMAC cost, probes timed relative to the period end, repeated periods.
