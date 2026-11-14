---------------------------- MODULE Sybil ----------------------------
(* Placement, privacy and sybil providers (E4: hoarding, duplicating, privacy).
   The writer places each chunk on R provider identities. One operator may run
   several identities (Sybils: one operator A). The writer wants
   - privacy: no operator sees more than MaxShare distinct chunks of the file,
   - independence: the R replicas of a chunk sit with different operators,
   - honest payment: every paid replica is a separate physical copy.
   Two defences are modelled as switches:
   - Attested:     the writer learns the operator of each identity (stake binding,
                   attestation) and applies the placement rules per operator.
                   Otherwise the rules apply per identity, which a sybil defeats.
   - ReplicaBound: the proof of storage is bound to the identity (a unique
                   encoding per replica), so an operator must keep a separate
                   physical copy per identity. Otherwise one copy answers the
                   probes of all its identities (dedup) and the operator is paid
                   for copies it does not keep.
   Duplicating or hoarding chunks as such is harmless here: it only hurts when it
   fakes independence (replicas at one operator) or payment (dedup). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Chunks, Ids,
          Sybils,        \* identities that belong to one operator
          R,             \* replicas per chunk
          MaxShare,      \* maximal number of distinct chunks per operator
          Attested,      \* BOOLEAN
          ReplicaBound   \* BOOLEAN

ASSUME Sybils \subseteq Ids /\ R \in Nat \ {0} /\ MaxShare \in Nat
ASSUME Attested \in BOOLEAN /\ ReplicaBound \in BOOLEAN

Operator(i) == IF i \in Sybils THEN CHOOSE s \in Sybils : TRUE ELSE i
\* what the writer can tell apart
Group(i) == IF Attested THEN Operator(i) ELSE i
\* what a physical copy answers for
Key(i) == IF ReplicaBound THEN i ELSE Operator(i)

VARIABLES place,    \* <<chunk, identity>> pairs chosen by the writer
          stored    \* <<chunk, key>> physical copies kept by the providers
vars == <<place, stored>>

TypeOK == place \subseteq Chunks \X Ids /\ stored \subseteq Chunks \X Ids

Init == place = {} /\ stored = {}

Replicas(c, pl) == {j \in Ids : <<c, j>> \in pl}
\* chunks placed (in pl) at identities i with F(i) = g
ChunksAt(F(_), g, pl) == {d \in Chunks : \E j \in Ids : F(j) = g /\ <<d, j>> \in pl}

\* the writer places a replica; the rules are applied per Group
Place(c, i) == /\ <<c, i>> \notin place
               /\ Cardinality(Replicas(c, place)) < R
               /\ \A j \in Replicas(c, place) : Group(j) # Group(i)
               /\ Cardinality(ChunksAt(Group, Group(i), place \cup {<<c, i>>})) <= MaxShare
               /\ place' = place \cup {<<c, i>>}
               /\ UNCHANGED stored

\* a provider keeps a physical copy
Store(c, i) == /\ <<c, i>> \in place /\ <<c, Key(i)>> \notin stored
               /\ stored' = stored \cup {<<c, Key(i)>>}
               /\ UNCHANGED place

Next == \E c \in Chunks, i \in Ids : Place(c, i) \/ Store(c, i)

Spec == Init /\ [][Next]_vars

----------------------------------------------------------------------
\* replicas whose probes are answered, hence paid
Paid == {x \in place : <<x[1], Key(x[2])>> \in stored}

\* every paid replica is a physical copy
CopiesPaidFor == Cardinality(Paid) <= Cardinality(stored)

\* the replicas of a chunk sit with different operators
Independent == \A x, y \in place : (x[1] = y[1] /\ x[2] # y[2]) => Operator(x[2]) # Operator(y[2])

\* no operator sees more than MaxShare chunks
OperatorShareOK == \A o \in Ids : Cardinality(ChunksAt(Operator, o, place)) <= MaxShare

\* every chunk has its R replicas. The rules above hold trivially if the writer places nothing,
\* so check that full placement is reachable: NeverAllPlaced is violated iff it is.
AllPlaced == \A c \in Chunks : Cardinality(Replicas(c, place)) = R
NeverAllPlaced == ~AllPlaced
=======================================================================
