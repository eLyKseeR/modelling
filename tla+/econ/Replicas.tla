---------------------------- MODULE Replicas ----------------------------
(* Re-replication after failed probes (E4: failures and partitions).
   A chunk is kept by R providers. The broker checks every provider holding it;
   a provider that is unreachable or too slow fails the check. Failures are
   often transient (a partition, a restart), and a failed check can trigger a
   copy to another provider. Without care a blip creates duplicates, which cost
   the writer storage fees and leak the chunk to more providers.

   Policy "naive":      replicate after one failed check; never remove copies.
   Policy "hysteresis": replicate only after K consecutive failed checks AND
                        only while fewer than R live copies exist; remove a copy
                        again when the live copies are above R.

   Network model: at most F providers are down at once, at most MaxEvents
   failures in total (keeps the state space finite). F < R: a live copy exists. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Providers,
          R,          \* target number of copies
          K,          \* consecutive failed checks that make a failure "real"
          F,          \* maximal number of providers down at the same time
          MaxEvents,  \* maximal number of failures in total
          Policy      \* "naive" | "hysteresis"

ASSUME R \in Nat \ {0} /\ K \in Nat \ {0} /\ F \in Nat /\ F < R /\ R <= Cardinality(Providers)
ASSUME Policy \in {"naive", "hysteresis"}

VARIABLES holds,      \* providers that hold a copy
          down,       \* providers currently unreachable
          strikes,    \* consecutive failed checks per provider (capped at K)
          events,     \* failures so far
          copies,     \* replications made so far
          realFailure \* some provider reached K consecutive failed checks
vars == <<holds, down, strikes, events, copies, realFailure>>

Threshold == IF Policy = "naive" THEN 1 ELSE K

TypeOK == /\ holds \subseteq Providers /\ down \subseteq Providers
          /\ strikes \in [Providers -> 0..K]
          /\ events \in 0..MaxEvents /\ copies \in Nat
          /\ realFailure \in BOOLEAN

Init == /\ holds \in {S \in SUBSET Providers : Cardinality(S) = R}
        /\ down = {} /\ strikes = [p \in Providers |-> 0]
        /\ events = 0 /\ copies = 0 /\ realFailure = FALSE

Fail(p) == /\ events < MaxEvents /\ p \notin down /\ Cardinality(down) < F
           /\ down' = down \cup {p} /\ events' = events + 1
           /\ UNCHANGED <<holds, strikes, copies, realFailure>>

Recover(p) == /\ p \in down
              /\ down' = down \ {p} /\ strikes' = [strikes EXCEPT ![p] = 0]
              /\ UNCHANGED <<holds, events, copies, realFailure>>

\* broker probe of a provider holding a copy
Check(p) == /\ p \in holds
            /\ LET s == IF p \in down THEN IF strikes[p] < K THEN strikes[p] + 1 ELSE K ELSE 0
               IN /\ strikes' = [strikes EXCEPT ![p] = s]
                  /\ realFailure' = (realFailure \/ s >= K)
            /\ UNCHANGED <<holds, down, events, copies>>

\* copy the chunk from a live holder to a live provider that has none
Replicate(p, q) == /\ p \in holds /\ strikes[p] >= Threshold
                   /\ holds \ down # {} /\ q \notin holds /\ q \notin down
                   /\ Policy = "hysteresis" => Cardinality(holds \ down) < R
                   /\ holds' = holds \cup {q} /\ copies' = copies + 1
                   /\ UNCHANGED <<down, strikes, events, realFailure>>

\* hysteresis: drop a surplus copy while R live copies remain
Prune(p) == /\ Policy = "hysteresis"
            /\ p \in holds /\ Cardinality(holds) > R
            /\ Cardinality((holds \ {p}) \ down) >= R
            /\ holds' = holds \ {p} /\ strikes' = [strikes EXCEPT ![p] = 0]
            /\ UNCHANGED <<down, events, copies, realFailure>>

Next == \E p \in Providers : Fail(p) \/ Recover(p) \/ Check(p) \/ Prune(p)
        \/ \E a, b \in Providers : Replicate(a, b)

Spec == Init /\ [][Next]_vars

----------------------------------------------------------------------
\* never more duplicates than the failures that may overlap
BoundedCopies == Cardinality(holds) <= R + F

\* a live copy always exists
Durable == holds \ down # {}

\* a transient blip (shorter than K checks) triggers no copy
NoReplicaWithoutRealFailure == copies > 0 => realFailure
=======================================================================
