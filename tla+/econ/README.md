# econ: the economic model

Money, escrow and the incentives of the parties: writer, broker, storage provider (SP), reader. Run all with `make econ econpos restore replicas sybil` in [`..`](../README.md).

**Steps E0-E5.** The model grew in six steps; the labels `E0`-`E5` below name them:

| step | what it adds | module |
|---|---|---|
| E0 | payment: the writer pays, the broker holds the money in escrow | `Econ` |
| E1 | settlement at period end: pass pays the SP, fail refunds the writer, the broker always keeps the fee | `Econ` |
| E2 | restore: the reader pays for getting chunks back; timeouts, nack with probe, reader and SP reputation, fee tier | `Restore` |
| E3 | the verdict comes from the proof-of-storage model (`PoS.tla`), no longer abstract | `EconPoS` |
| E4 | critics: failures and partitions, duplicates, hoarding, privacy, sybils, cancelled account | `Econ`, `Replicas`, `Sybil` |
| E5 | incentives: SP stake and costs; no deviation may beat the honest profit (`NoGain`) | `EconPoS` |

The map:

![Model map](../out/econ/econ%20overview.png)

Every module has configs that must pass and *negative* configs that must violate one property (so the properties are not vacuous). Diagram per config: [`../out/econ_configs`](../out/econ_configs/overview.png).

![configs](../out/econ_configs/overview.png)

## Econ.tla: payment, escrow, settlement (E0, E1, E4 cancelled account)

![lifecycle](../out/econ/Econ%20request%20lifecycle.png)

A request goes `idle -Pay-> active -Prove-> judged -Settle-> paid | refunded`. The writer pays `Price` into escrow at the broker; the verdict (`pass`/`fail`) is abstract here. The broker keeps `Fee` (`FeePct` percent) in every case; on `pass` the rest goes to the SP, on `fail` back to the writer. The writer may cancel the account (`Cancel`) before a refund arrives; a refund for a closed account is parked (`ParkRefund`) until `Claim`.

The configs have three requests and funds for two (`WriterInit = 250`, `Price = 100`): two requests are open at once, and the third can be paid only after a refund.

Checked: `Conservation` (incl. parked, withdrawn, burned), `EscrowExact`, `BrokerIncome`, `SpIncome`, `PaidOnlyWithProof`, `RefundOnFail`, `NoBurn`; liveness `Settled`, `Claimed`.

| config | result |
|---|---|
| `Econ` | all hold |
| `Econ_collude` | broker pays the SP despite a failed proof: `PaidOnlyWithProof` violated. A single broker needs audit, or many brokers |
| `Econ_burn` | refund for a cancelled account without parking: `NoBurn` violated |

## EconPoS.tla: the verdict comes from the PoS model (E3, E5)

![settlement](../out/econ/EconPoS%20settlement.png)

One request. `PoS.tla` (symlinked from `../pos`, `P == INSTANCE PoS`) runs after the writer paid; `Prove` takes `P!proof`. The SP posts a stake (`Stake`): returned on `pass`, to the writer on `fail`. The SP has costs (`StoreCost` per chunk, `RelayCost` per accepted relay, `DropSaving` per dropped chunk). **`NoGain`: no deviation beats the honest profit.** **`WriterWhole`: a failed proof costs the writer nothing**, the stake covers the fee the broker keeps.

| config | SP behaviour | result |
|---|---|---|
| `EconPoS` | honest | SP paid; money follows the proof; `NoGain` |
| `EconPoS_lost`, `EconPoS_facade` | lost chunk, slow relay | never paid; `NoGain`; writer whole (`WriterWhole`) |
| `EconPoS_part_ok` | partition of 2 ticks | still paid |
| `EconPoS_slow` | too slow | `NeverRefunded` violated (refund) |
| `EconPoS_part_long` | partition of 4 ticks | honest SP refunded and loses stake: `NeverRefunded` violated |
| `EconPoS_facade_bad`, `EconPoS_facade_gain` | relay within deadline | SP is paid (`NeverPaid`) and profits more than honest (`NoGain`) violated |
| `EconPoS_drop`, `EconPoS_drop_gain` | drops a chunk after the last probe | paid without storing (`PaidImpliesHeld`), profit above honest (`NoGain`) violated |
| `EconPoS_nostake` | lost chunk, `Stake = 0` | the writer loses the fee on a failed proof: `WriterWhole` violated |

Findings: the stake must cover the fee (`Stake >= Fee`), else a failed proof costs the writer the fee (`EconPoS_nostake`). `NoGain` alone does not need a stake: an unpaid SP is below the honest profit anyway. A stake punishes only *detected* cheating. Two cheats stay profitable: a facade inside a lax deadline, and a drop after the last probe. Open remedies: tight deadline (see `pos`), probes close to the period end, payout delay with clawback. A long network partition hits the honest SP as hard as a cheater: that is the SLA limit.

## Restore.tla: paying for a restore (E2)

![restore](../out/econ/Restore%20policies.png)

The reader escrows `N` chunk prices and pays a fee that the broker keeps at once (not refundable, so misbehaving does not save it). The question is when the broker releases the escrow to the SP. Per chunk the reader asks the SP (`Ask`), the SP delivers and notes it to the broker (`Deliver`), the reader acknowledges (`Ack`) or rejects a bad chunk (`Nack`). `SpLoss` and `ReaderLoss` count the chunk prices at risk.

Reputation of reader (`repR`) and SP (`repS`) is an integer EMA as in `PoS.tla`, starting at 100; an ack raises both. Rounding down, the EMA never returns to 100 after a penalty, so "blamed" in the properties means "below 100 at the end" (valid only for that start value). The reader's reputation sets the fee tier of its next restore (`NextFee`: `FeeLow` at or above `Thr`, else `FeeHigh`).

What the broker sees, and who is blamed:

| situation | broker's action | reputation |
|---|---|---|
| ack | release (perchunk) | both up |
| nack, the SP answers a probe for the chunk | nack was false: release the price | reader down |
| nack, the SP fails the probe | nack was honest: close, refund the rest | SP down |
| nobody progresses for `Window` ticks (no request, no delivery or no ack) | timeout: close, refund the rest | both slightly down (`Slight`): who stalled is not provable |

Deviations: `SpFaulty` (delivers nothing), `SpCorrupt` (bad chunks; `SpHolds`: can still serve the chunk when probed), `ReaderWithholds` (never acks), `ReaderIdle` (never asks), `ReaderLies` (nacks good chunks).

| config | result |
|---|---|
| `Restore_perchunk_honest` | complete, no loss, nobody blamed (`HonestNotBlamed`) |
| `Restore_perchunk_reader`, `Restore_perchunk_sp`, `Restore_perchunk_idle` | either side loses at most one chunk (`SpLossBounded`, `ReaderLossBounded`); timeout lowers both reputations (`ReaderPenalised`, `SpPenalised`) |
| `Restore_nack_honest` | bad chunk, probe fails: the SP is blamed, the reader is not (`NackJudged`) |
| `Restore_nack_lie` | false nack, probe passes: the reader is blamed, the SP is paid (`NackJudged`) |
| `Restore_upfront_sp` | release at once: a faulty SP keeps all N prices (`ReaderLossBounded` violated) |
| `Restore_after_reader` | release after delivery: a reader who never acks gets all N chunks free (`SpLossBounded` violated) |
| `Restore_fee_refund` | fee refunded on close: a withholding reader gets it back (`FeeKept` violated) |
| `Restore_nopenalty` | timeouts without penalty: a withholding reader keeps its reputation (`ReaderPenalised` violated) |
| `Restore_nack_noprobe` | the broker trusts a nack: a lying reader gets a chunk free and the SP is blamed (`NackJudged` violated) |
| `Restore_nack_selective` | the SP sends a bad chunk but passes the probe: the honest reader is blamed (`NackJudged` violated) |
| `Restore_nack_signed` | as `Restore_nack_selective`, but the SP signs each delivery (`Signed`): the nack carries the bad chunk and the SP is blamed |
| `Restore_tier` | withholding reader, `Thr = 90`: one timeout (100 to 87) moves it to the high fee tier (`TierRaised`) |
| `Restore_tier_soft` | same with `Thr = 70`: 87 stays in the low tier, the next restore costs the same (`TierRaised` violated) |

Also checked: `MoneyConserved` (escrow + fee = released + refunded + kept), `EscrowCovers`, `Complete`, liveness `Terminates`.

Findings: release per chunk, on acknowledgement, and let the SP deliver chunk k+1 only after ack k. Chunks are content addressed, so the reader can verify a chunk before acknowledging. A nack must be checked by a probe, otherwise a reader gets chunks free. A probe tests whether the SP *can* serve the chunk, not what it *sent*: an SP that sends garbage selectively passes it (`Restore_nack_selective`). Remedy: the SP signs each delivery, so a nack carries non-repudiable proof of what was sent (`Restore_nack_signed`). A timeout cannot be attributed; the slight penalty to both only separates the parties over many restores with different counterparties (not modelled). A single timeout (W=4, Slight=50) lowers 100 to 87, still in the low fee tier at `Thr = 70` (`Restore_tier_soft`); only a threshold above 87 makes one timeout cost the reader (`Restore_tier`). Reputation is a soft price, the per-chunk release is the hard bound.

## Replicas.tla: failures, partitions, duplicates (E4)

![replicas](../out/econ/Replicas%20states.png)

`R` providers keep a chunk; failures are transient (at most `F` at once). Policy `naive` copies after one failed check and never removes copies; `hysteresis` copies after `K` consecutive failed checks, only while fewer than `R` live copies exist, and prunes surplus copies.

| config | result |
|---|---|
| `Replicas_hysteresis` | `BoundedCopies` (copies <= R+F), `Durable`, `NoReplicaWithoutRealFailure` hold |
| `Replicas_naive` | `BoundedCopies` violated: duplicates pile up |
| `Replicas_naive_blip` | a blip already triggers a copy (`NoReplicaWithoutRealFailure` violated) |

## Sybil.tla: placement, privacy, hoarding (E4)

![sybil](../out/econ/Sybil%20placement.png)

The writer places each chunk on `R` provider identities. One operator may run several (`Sybils`). Wanted: no operator sees more than `MaxShare` chunks (privacy), replicas of a chunk at different operators (independence), and every paid replica is a separate physical copy. Switches: `Attested` (the writer applies the rules per operator, not per identity) and `ReplicaBound` (proofs bound to the identity, so one copy cannot answer for several identities).

| config | result |
|---|---|
The configs have 3 chunks, `R = 2`, `MaxShare = 2` and 4 identities, of which `i1`, `i2` belong to one operator A (except `Sybil_honest`, `Sybil_capacity`). The three rules only say "nothing bad was placed"; a writer who places nothing satisfies them. `AllPlaced` (every chunk has `R` replicas) is therefore checked for reachability: `NeverAllPlaced` must be violated.

| config | result |
|---|---|
| `Sybil_honest` | all hold (independent operators) |
| `Sybil_attested` | all hold despite a sybil operator: attestation alone suffices |
| `Sybil_bound` | replica-bound proofs alone (unattested): `CopiesPaidFor` holds, payment is honest |
| `Sybil_capacity` | attested, but only 2 operators (A, `i3`): the file is never fully placed (`NeverAllPlaced` holds) |
| `Sybil_placeable` | attested, 3 operators (A, `i3`, `i4`): the file can be fully placed (`NeverAllPlaced` violated, the counterexample is a placement) |
| `Sybil_dedup` | unattested + not replica-bound: one copy paid twice (`CopiesPaidFor` violated) |
| `Sybil_unattested` | replicas of a chunk at one operator (`Independent` violated) |
| `Sybil_share` | one operator holds more than `MaxShare` chunks (`OperatorShareOK` violated) |

Finding on hoarding / duplicating: copies kept by an SP as such are harmless or good for availability. They hurt only when they fake independence or payment. Operator attestation fixes all three rules; replica-bound proofs alone fix only the payment (`Sybil_bound` vs `Sybil_unattested`, `Sybil_share`).

Finding on capacity: the rules need enough independent operators, at least `R` and at least `chunks x R / MaxShare` (`Sybil_capacity`: 2 operators for 6 placements of at most 2 each per operator, too few). And placing greedily can dead-end even when a full placement exists (e.g. two chunks at the same two operators fill both): the writer must plan the placement or keep spare operators.

## Not modelled

Real LXR amounts and prices over time, several periods and renewals, several brokers (only the single-broker deviation `Econ_collude`), lost messages and retries in a restore, probabilistic failure rates (TLC is not probabilistic: failures are bounded, not weighted).
