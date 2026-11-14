---------------------------- MODULE Econ ----------------------------
(* Payment, escrow and settlement of storage requests (steps E0, E1, E4 in README.md).
   Parties: writer (pays for storing), broker (escrow, fee), sp (storage provider).
   A storage request q:  idle --Pay--> active --Prove--> judged --Settle--> paid | refunded
   - Pay:    the writer pays Price; the broker holds it in escrow.
   - Prove:  the period is over; the broker records the proof-of-storage verdict.
             Abstract here (nondeterministic); pos/PoS.tla gives it a meaning (step E3).
   - Settle: the broker keeps Fee in every case. Verdict "pass": the rest goes to the sp.
             Verdict "fail": the rest goes back to the writer.
   Money is a natural number; Fee = Price * FeePct div 100.
   BrokerPaysAnyway models a deviating broker who pays the sp although the proof failed.

   Cancelled account: the refund arrives up to a period after the payment.
   The writer may cancel the account meanwhile (Cancel: the funds are withdrawn,
   the account is closed). A refund for a closed account is parked at the broker
   (ParkRefund = TRUE) until the owner claims it, or lost (FALSE, naive). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Reqs,              \* storage requests
          Price,             \* LXR per request and period
          FeePct,            \* broker fee in percent of Price
          WriterInit,        \* initial funds of the writer
          BrokerPaysAnyway,  \* BOOLEAN: deviating broker
          ParkRefund         \* BOOLEAN: park refunds for closed accounts (else they are lost)

ASSUME Price \in Nat \ {0}
ASSUME FeePct \in 0..100
ASSUME WriterInit \in Nat
ASSUME BrokerPaysAnyway \in BOOLEAN /\ ParkRefund \in BOOLEAN

Fee == (Price * FeePct) \div 100
Parties == {"writer", "broker", "sp"}
Total == WriterInit            \* all money in the system; broker and sp start with 0

VARIABLES bal,       \* balance of each party
          escrow,    \* funds held by the broker for open requests
          st,        \* state of each request
          verdict,   \* PoS verdict of each request: "none" | "pass" | "fail"
          acct,      \* writer account: "open" | "closed"
          unclaimed, \* refunds parked for a closed account
          withdrawn, \* funds that left the system (writer withdrawals and claims)
          burned     \* refunds lost
vars == <<bal, escrow, st, verdict, acct, unclaimed, withdrawn, burned>>

States == {"idle", "active", "judged", "paid", "refunded"}

TypeOK == /\ bal \in [Parties -> Nat]
          /\ escrow \in Nat
          /\ st \in [Reqs -> States]
          /\ verdict \in [Reqs -> {"none", "pass", "fail"}]
          /\ acct \in {"open", "closed"}
          /\ unclaimed \in Nat /\ withdrawn \in Nat /\ burned \in Nat

Init == /\ bal = [p \in Parties |-> IF p = "writer" THEN WriterInit ELSE 0]
        /\ escrow = 0
        /\ st = [q \in Reqs |-> "idle"]
        /\ verdict = [q \in Reqs |-> "none"]
        /\ acct = "open" /\ unclaimed = 0 /\ withdrawn = 0 /\ burned = 0

Pay(q) == /\ st[q] = "idle" /\ acct = "open"
          /\ bal["writer"] >= Price
          /\ bal' = [bal EXCEPT !["writer"] = @ - Price]
          /\ escrow' = escrow + Price
          /\ st' = [st EXCEPT ![q] = "active"]
          /\ UNCHANGED <<verdict, acct, unclaimed, withdrawn, burned>>

Prove(q) == /\ st[q] = "active"
            /\ \E v \in {"pass", "fail"} : verdict' = [verdict EXCEPT ![q] = v]
            /\ st' = [st EXCEPT ![q] = "judged"]
            /\ UNCHANGED <<bal, escrow, acct, unclaimed, withdrawn, burned>>

Settle(q) ==
  LET net  == Price - Fee
      toSp == verdict[q] = "pass" \/ BrokerPaysAnyway
      open == acct = "open"
  IN /\ st[q] = "judged"
     /\ escrow' = escrow - Price
     /\ st' = [st EXCEPT ![q] = IF toSp THEN "paid" ELSE "refunded"]
     /\ bal' = [bal EXCEPT !["broker"] = @ + Fee,
                           !["sp"]     = @ + (IF toSp THEN net ELSE 0),
                           !["writer"] = @ + (IF ~toSp /\ open THEN net ELSE 0)]
     \* a refund for a closed account is parked, or lost (naive)
     /\ unclaimed' = unclaimed + (IF ~toSp /\ ~open /\ ParkRefund THEN net ELSE 0)
     /\ burned'    = burned    + (IF ~toSp /\ ~open /\ ~ParkRefund THEN net ELSE 0)
     /\ UNCHANGED <<verdict, acct, withdrawn>>

\* the writer cancels the account and withdraws what is left
Cancel == /\ acct = "open"
          /\ acct' = "closed"
          /\ withdrawn' = withdrawn + bal["writer"]
          /\ bal' = [bal EXCEPT !["writer"] = 0]
          /\ UNCHANGED <<escrow, st, verdict, unclaimed, burned>>

\* the owner of the closed account collects the parked refunds
Claim == /\ acct = "closed" /\ unclaimed > 0
         /\ withdrawn' = withdrawn + unclaimed
         /\ unclaimed' = 0
         /\ UNCHANGED <<bal, escrow, st, verdict, acct, burned>>

Next == Cancel \/ Claim \/ \E q \in Reqs : Pay(q) \/ Prove(q) \/ Settle(q)

Spec == Init /\ [][Next \/ UNCHANGED vars]_vars /\ WF_vars(Next)

----------------------------------------------------------------------
Count(S) == Cardinality({q \in Reqs : st[q] \in S})
Sum == bal["writer"] + bal["broker"] + bal["sp"]

\* no money is created or lost
Conservation == Sum + escrow + unclaimed + withdrawn + burned = Total

\* a refund is never lost, also not for a closed account
NoBurn == burned = 0

\* escrow is exactly the price of the open requests
EscrowExact == escrow = Price * Count({"active", "judged"})

\* the broker earns the fee on every settled request, and only on those
BrokerIncome == bal["broker"] = Fee * Count({"paid", "refunded"})

\* the sp is paid only for requests with a passed proof, and gets the rest of the price
PaidOnlyWithProof == \A q \in Reqs : st[q] = "paid" => verdict[q] = "pass"
SpIncome == bal["sp"] = (Price - Fee) * Count({"paid"})

\* a failed proof returns the funds (less fee) to the writer
RefundOnFail == \A q \in Reqs : st[q] = "refunded" => verdict[q] = "fail"

(* Liveness: a paid request is eventually settled; parked refunds are claimed
   (assumes the owner eventually claims) *)
Claimed == unclaimed > 0 ~> unclaimed = 0
Settled == \A q \in Reqs : st[q] = "active" ~> st[q] \in {"paid", "refunded"}
=======================================================================
