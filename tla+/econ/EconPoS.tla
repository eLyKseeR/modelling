------------------------- MODULE EconPoS -------------------------
(* One storage request whose verdict comes from the proof-of-storage model
   (PoS.tla, symlinked from ../pos), with SP stake and costs (steps E3, E5 in README.md).

     idle --Pay--> active --(PoS probes the SP; period closes)--> Prove --> judged --Settle--> paid | refunded

   The PoS actions run only while the request is active, i.e. after the writer
   has paid. The verdict is "pass" iff the PoS proof is TRUE.
   Settlement as in Econ.tla: the broker keeps Fee in every case; pass: the
   rest goes to the SP; fail: back to the writer.
   Stake: the SP posts Stake with the request; it gets it back on a
   pass, and loses it to the writer on a fail. The SP has costs (StoreCost per
   chunk kept, RelayCost per accepted relay, DropSaving per chunk dropped
   before settlement); NoGain checks that no deviation beats the honest profit.
   Constants of PoS keep their names (they are passed on unchanged). *)
EXTENDS Integers, FiniteSets

CONSTANTS Price, FeePct, WriterInit, SpInit, Stake, StoreCost, RelayCost, DropSaving
CONSTANTS Chunks, Ranges, HeldRanges, Nonces, HeldInit, AllowDrop, Other, RelayLat,
          MaxLat, Budget, MaxTime, PartLen, W, Thr, MinProbes, None

ASSUME Price \in Nat \ {0}
ASSUME FeePct \in 0..100
ASSUME WriterInit \in Nat
ASSUME SpInit \in Nat /\ Stake \in Nat /\ Stake <= SpInit

VARIABLES bal, escrow, st, verdict
VARIABLES held, chal, resp, used, verified, now, sent, rep, fake, cheated,
          cut, cutUsed, closed, proof

P == INSTANCE PoS

econvars == <<bal, escrow, st, verdict>>
pvars == <<held, chal, resp, used, verified, now, sent, rep, fake, cheated, cut, cutUsed, closed, proof>>
vars == <<econvars, pvars>>

Fee == (Price * FeePct) \div 100
Parties == {"writer", "broker", "sp"}
Total == WriterInit + SpInit

TypeOK == /\ bal \in [Parties -> Nat]
          /\ escrow \in Nat
          /\ st \in {"idle", "active", "judged", "paid", "refunded"}
          /\ verdict \in {"none", "pass", "fail"}
          /\ P!TypeOK

Init == /\ bal = [p \in Parties |-> CASE p = "writer" -> WriterInit [] p = "sp" -> SpInit [] OTHER -> 0]
        /\ escrow = 0
        /\ st = "idle"
        /\ verdict = "none"
        /\ P!Init

Pay == /\ st = "idle"
       /\ bal["writer"] >= Price /\ bal["sp"] >= Stake
       /\ bal' = [bal EXCEPT !["writer"] = @ - Price, !["sp"] = @ - Stake]
       /\ escrow' = escrow + Price + Stake
       /\ st' = "active"
       /\ UNCHANGED <<verdict, pvars>>

\* the provider and the broker run the PoS model while the request is active
PoSStep == /\ st = "active"
           /\ P!Next
           /\ UNCHANGED econvars

Prove == /\ st = "active" /\ closed
         /\ verdict' = IF proof THEN "pass" ELSE "fail"
         /\ st' = "judged"
         /\ UNCHANGED <<bal, escrow, pvars>>

Settle == /\ st = "judged"
          /\ escrow' = escrow - Price - Stake
          /\ IF verdict = "pass"
               THEN /\ bal' = [bal EXCEPT !["broker"] = @ + Fee, !["sp"] = @ + (Price - Fee) + Stake]
                    /\ st' = "paid"
               ELSE /\ bal' = [bal EXCEPT !["broker"] = @ + Fee, !["writer"] = @ + (Price - Fee) + Stake]
                    /\ st' = "refunded"
          /\ UNCHANGED <<verdict, pvars>>

\* settled (stuttering only here, so TLC still reports a deadlock before the end)
Done == st \in {"paid", "refunded"} /\ UNCHANGED vars

Next == Pay \/ PoSStep \/ Prove \/ Settle \/ Done

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

----------------------------------------------------------------------
Sum == bal["writer"] + bal["broker"] + bal["sp"]
Open == IF st \in {"active", "judged"} THEN Price + Stake ELSE 0

Conservation == Sum + escrow = Total
EscrowExact == escrow = Open
BrokerIncome == bal["broker"] = IF st \in {"paid", "refunded"} THEN Fee ELSE 0

\* money follows the PoS proof
PaidOnlyWithProof == st = "paid" => closed /\ proof
RefundOnlyWithoutProof == st = "refunded" => closed /\ ~proof

\* scenario checks (configs choose the SP behaviour)
NeverRefunded == st # "refunded"      \* honest SP: always paid
NeverPaid == st # "paid"              \* SP lacking a chunk: never paid
\* the SP is paid only while it still holds all chunks (false if it drops after the last probe)
PaidImpliesHeld == st = "paid" => held = Chunks

\* E5: profit of the SP after settlement, and the profit of an honest one
SpCost == StoreCost * Cardinality(HeldInit) - DropSaving * Cardinality(HeldInit \ held)
          + RelayCost * Cardinality(cheated)
SpProfit == bal["sp"] - SpInit + 0 - SpCost
HonestProfit == (Price - Fee) - StoreCost * Cardinality(Chunks)
NoGain == st \in {"paid", "refunded"} => SpProfit <= HonestProfit
\* a failed proof costs the writer nothing: the stake covers the fee (needs Stake >= Fee)
WriterWhole == st = "refunded" => bal["writer"] >= WriterInit

\* the request ends
Settled == st = "active" ~> st \in {"paid", "refunded"}
=======================================================================
