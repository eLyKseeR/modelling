---------------------------- MODULE Restore ----------------------------
(* Restore payment (step E2 in README.md): a reader restores N chunks from a storage provider (SP)
   through the broker. The reader pays the whole price at once into escrow at
   the broker, plus a fee that the broker keeps at once (not refundable). The
   question is WHEN the broker releases the escrow to the SP. Neither side can
   prove to the broker what was (not) transferred, so each fears the other.
   The loss each side can suffer is what the release policy bounds.

   Policy (constant):
   - "upfront":  all N chunk prices are released to the SP at once.
                 A faulty SP keeps the money without delivering.
   - "after":    released after the last chunk was acknowledged.
                 A reader who withholds the receipt gets all N chunks free.
   - "perchunk": the SP delivers chunk k+1 only after the reader acknowledged
                 chunk k; the price of chunk k is released on the ack.
                 Either side loses at most one chunk price.

   Per chunk: the reader asks the SP (Ask), the SP delivers and notes the
   delivery to the broker (Deliver), the reader acknowledges (Ack) or, for a
   bad chunk, rejects it (Nack). Chunks are content addressed: the reader can
   verify a chunk. The broker does not trust a nack: it probes the SP for that
   chunk (Judge). The SP answers the probe: the nack was false, the reader is
   penalised and the SP paid for the chunk. The SP fails: the nack was honest,
   the SP is penalised and the restore ends.

   Reputation: reader (repR) and SP (repS), integer EMA as in PoS.tla, both start at 100. An ack
   raises both. When nobody can progress, time passes; after Window ticks the
   broker times out. Who stalled is not provable (no request, no delivery, or
   no ack look the same to the broker), so both get a slight penalty. The
   reader's reputation sets the fee tier of its next restore (NextFee).

   Deviations (constants): SpFaulty (delivers nothing), SpCorrupt (delivers bad
   chunks), SpHolds (can serve the chunk when probed), ReaderWithholds (never
   acknowledges), ReaderIdle (never asks the SP), ReaderLies (may nack a good
   chunk). Switches for negative tests: FeeRefundable, Penalty, Probe; remedy: Signed. *)
EXTENDS Naturals

CONSTANTS N,                 \* chunks to restore
          Price,             \* LXR per chunk
          Policy,            \* "upfront" | "after" | "perchunk"
          SpFaulty,          \* BOOLEAN: SP delivers nothing
          SpCorrupt,         \* BOOLEAN: SP delivers bad chunks
          SpHolds,           \* BOOLEAN: SP answers a probe for the chunk correctly
          ReaderWithholds,   \* BOOLEAN: reader never acknowledges (nor rejects)
          ReaderIdle,        \* BOOLEAN: reader never asks the SP for a chunk
          ReaderLies,        \* BOOLEAN: reader may nack a good chunk
          Window,            \* ticks the broker waits before a timeout
          W,                 \* EMA window
          Thr,               \* reputation for the low fee tier
          Slight,            \* EMA sample on a timeout (blame is not provable)
          FeeLow, FeeHigh,   \* fee in percent of N * Price, by reader reputation
          FeeRefundable,     \* BOOLEAN (negative test): the fee is refunded on close
          Penalty,           \* BOOLEAN: a timeout lowers the reputations
          Probe,             \* BOOLEAN: the broker probes the SP on a nack (else trusts it)
          Signed             \* BOOLEAN: the SP signs each delivery; a nack carries the signed chunk

ASSUME N \in Nat \ {0} /\ Price \in Nat \ {0}
ASSUME Policy \in {"upfront", "after", "perchunk"}
ASSUME \A b \in {SpFaulty, SpCorrupt, SpHolds, ReaderWithholds, ReaderIdle, ReaderLies,
                  FeeRefundable, Penalty, Probe, Signed} : b \in BOOLEAN
ASSUME W \in Nat \ {0} /\ Window \in Nat
ASSUME {Thr, Slight, FeeLow, FeeHigh} \subseteq 0..100

VARIABLES phase,     \* "new" | "running" | "probing" | "closed"
          asked,     \* chunks the reader asked the SP for
          delivered, \* chunks the reader received (the SP noted them to the broker)
          acked,     \* chunks settled for the SP: acknowledged, or nack refuted by a probe
          released,  \* chunks whose price went to the SP
          nacked,    \* the reader rejected a chunk
          escrow,    \* chunk prices held by the broker
          fee,       \* fee paid with the request
          kept,      \* fee kept by the broker
          refunded,  \* returned to the reader on close
          now,       \* ticks waited in a stall
          repR,      \* reader reputation 0..100
          repS       \* SP reputation 0..100
vars == <<phase, asked, delivered, acked, released, nacked, escrow, fee, kept, refunded,
          now, repR, repS>>

TypeOK == /\ phase \in {"new", "running", "probing", "closed"}
          /\ asked \in 0..N /\ delivered \in 0..N /\ acked \in 0..N /\ released \in 0..N
          /\ nacked \in BOOLEAN
          /\ {escrow, fee, kept, refunded} \subseteq Nat
          /\ now \in 0..Window + 1
          /\ repR \in 0..100 /\ repS \in 0..100

Ema(r, sample) == (r * (W - 1) + sample) \div W
FeeFor(r) == (N * Price * (IF r >= Thr THEN FeeLow ELSE FeeHigh)) \div 100
\* what this reader pays for its next restore of the same size
NextFee == FeeFor(repR)

Init == /\ phase = "new" /\ asked = 0 /\ delivered = 0 /\ acked = 0 /\ released = 0
        /\ nacked = FALSE /\ escrow = 0 /\ fee = 0 /\ kept = 0 /\ refunded = 0
        /\ now = 0 /\ repR = 100 /\ repS = 100

\* close: the unreleased escrow returns to the reader; the fee only if FeeRefundable
Settle == /\ phase' = "closed"
          /\ refunded' = escrow - released * Price + (IF FeeRefundable THEN fee ELSE 0)
          /\ kept' = IF FeeRefundable THEN 0 ELSE fee

\* the reader pays escrow and fee at once; the broker keeps the fee (upfront: releases at once)
Request == /\ phase = "new"
           /\ phase' = "running"
           /\ escrow' = N * Price
           /\ fee' = FeeFor(repR) /\ kept' = fee'
           /\ released' = IF Policy = "upfront" THEN N ELSE 0
           /\ UNCHANGED <<asked, delivered, acked, nacked, refunded, now, repR, repS>>

CanAsk == ~ReaderIdle /\ asked = delivered /\ asked < N
CanDeliver == /\ ~SpFaulty /\ delivered < asked
              /\ (Policy = "perchunk" => acked = delivered)  \* perchunk: wait for the ack
CanAck == ~ReaderWithholds /\ ~SpCorrupt /\ acked < delivered
CanNack == ~ReaderWithholds /\ (SpCorrupt \/ ReaderLies) /\ acked < delivered
CanRelease == Policy = "after" /\ acked = N /\ released = 0
Done == acked = N /\ released = N

\* reader: ask the SP for the next chunk (with the reference the broker gave)
Ask == /\ phase = "running" /\ CanAsk
       /\ asked' = asked + 1
       /\ UNCHANGED <<phase, delivered, acked, released, nacked, escrow, fee, kept, refunded, now, repR, repS>>

\* SP: deliver the chunk and note the delivery to the broker
Deliver == /\ phase = "running" /\ CanDeliver
           /\ delivered' = delivered + 1
           /\ UNCHANGED <<phase, asked, acked, released, nacked, escrow, fee, kept, refunded, now, repR, repS>>

\* reader: acknowledge a received chunk; perchunk releases its price; both gain reputation
Ack == /\ phase = "running" /\ CanAck
       /\ acked' = acked + 1
       /\ released' = IF Policy = "perchunk" THEN released + 1 ELSE released
       /\ repR' = Ema(repR, 100) /\ repS' = Ema(repS, 100)
       /\ UNCHANGED <<phase, asked, delivered, nacked, escrow, fee, kept, refunded, now>>

\* reader: reject a received chunk; the broker holds its price and judges
Nack == /\ phase = "running" /\ CanNack
        /\ phase' = "probing" /\ nacked' = TRUE
        /\ UNCHANGED <<asked, delivered, acked, released, escrow, fee, kept, refunded, now, repR, repS>>

\* broker: judge the rejected chunk. Signed: the nack carries the chunk the SP signed, so the
\* broker sees what was sent. Else it probes the SP (abstract PoS probe: the answer is SpHolds),
\* which shows only what the SP can serve; without Probe it trusts the nack.
Judge == /\ phase = "probing"
         /\ IF (IF Signed THEN ~SpCorrupt ELSE Probe /\ SpHolds)
            THEN \* the SP can serve the chunk: the nack was false
                 /\ phase' = "running"
                 /\ acked' = acked + 1
                 /\ released' = IF Policy = "perchunk" THEN released + 1 ELSE released
                 /\ repR' = Ema(repR, 0)
                 /\ UNCHANGED <<repS, kept, refunded>>
            ELSE \* the SP fails the probe (or is not probed): the nack stands, the restore ends
                 /\ Settle
                 /\ repS' = Ema(repS, 0)
                 /\ UNCHANGED <<acked, released, repR>>
         /\ UNCHANGED <<asked, delivered, nacked, escrow, fee, now>>

\* "after": the broker releases all once the reader acked all
Release == /\ phase = "running" /\ CanRelease
           /\ released' = N
           /\ UNCHANGED <<phase, asked, delivered, acked, nacked, escrow, fee, kept, refunded, now, repR, repS>>

\* all chunks settled
Close == /\ phase = "running" /\ Done
         /\ Settle
         /\ UNCHANGED <<asked, delivered, acked, released, nacked, escrow, fee, now, repR, repS>>

\* nobody can progress. shortcut: time passes only in a stall, and a stall ends the
\* restore (deviations are permanent), so now counts the ticks of that stall; add a
\* start time per wait once lost messages and retries are modelled.
Stalled == phase = "running" /\ ~(CanAsk \/ CanDeliver \/ CanAck \/ CanNack \/ CanRelease \/ Done)

Tick == /\ Stalled /\ now <= Window
        /\ now' = now + 1
        /\ UNCHANGED <<phase, asked, delivered, acked, released, nacked, escrow, fee, kept, refunded, repR, repS>>

\* deadline passed: who stalled is not provable, so both get a slight penalty
Timeout == /\ Stalled /\ now > Window
           /\ Settle
           /\ repR' = IF Penalty THEN Ema(repR, Slight) ELSE repR
           /\ repS' = IF Penalty THEN Ema(repS, Slight) ELSE repS
           /\ UNCHANGED <<asked, delivered, acked, released, nacked, escrow, fee, now>>

\* closed (stuttering only here, so TLC still reports a deadlock before the end)
Finished == phase = "closed" /\ UNCHANGED vars

Next == Finished \/ Request \/ Ask \/ Deliver \/ Ack \/ Nack \/ Judge \/ Release \/ Close \/ Tick \/ Timeout

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

----------------------------------------------------------------------
\* what each side lost, counted in chunk prices, once the restore is closed
\* the SP delivered chunks that were not released to it
SpLoss == IF delivered > released THEN delivered - released ELSE 0
\* the reader's money went to the SP without chunks in return
ReaderLoss == IF released > delivered THEN released - delivered ELSE 0

Closed == phase = "closed"
Honest == ~SpFaulty /\ ~SpCorrupt /\ ~ReaderWithholds /\ ~ReaderIdle /\ ~ReaderLies

\* the exposure of each side is at most one chunk price
SpLossBounded == Closed => SpLoss <= 1
ReaderLossBounded == Closed => ReaderLoss <= 1

\* the escrow always covers what was not released
EscrowCovers == phase # "new" => escrow >= released * Price

\* every coin paid in went to the SP, back to the reader, or to the broker
MoneyConserved == Closed => released * Price + refunded + kept = escrow + fee

\* the fee is paid at once and never comes back: misbehaving does not save it
FeeKept == Closed => kept = fee

\* honest parties: the restore completes, the SP is fully paid, nobody is blamed
Complete == Closed /\ Honest => delivered = N /\ released = N
HonestNotBlamed == Closed /\ Honest => repR = 100 /\ repS = 100

\* Blame: from 100 the integer EMA never returns to 100 (rounding down), so rep < 100 at the end
\* means penalised at least once. shortcut: holds only for the start value 100; with a lower start
\* state the blame at the judging / timeout step instead (action property).
\* a stalling party loses reputation (and the reader does not get a cheaper next restore)
ReaderPenalised == Closed /\ (ReaderWithholds \/ ReaderIdle) => repR < 100 /\ NextFee >= fee
\* a stalling reader pays more for its next restore (holds only if one timeout drops it below Thr)
TierRaised == Closed /\ (ReaderWithholds \/ ReaderIdle) => NextFee > fee
SpPenalised == Closed /\ SpFaulty => repS < 100

\* a nack is judged right: honest (bad chunk) blames the SP only; false blames the
\* reader only and the SP is paid for every chunk it delivered
NackJudged == Closed /\ nacked =>
                IF SpCorrupt THEN repS < 100 /\ repR = 100
                             ELSE repR < 100 /\ repS = 100 /\ SpLoss = 0

(* Liveness: the restore ends *)
Terminates == <>Closed
=======================================================================
