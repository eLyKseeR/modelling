---------------------------- MODULE PoS ----------------------------
(* Proof of Storage: one broker probes one storage provider (SP) for one period.
   The broker sends a challenge (chunk, byte range, nonce). The SP returns
   the HMAC of that range keyed by the nonce. The broker checks it against
   its own reference copy. HMAC is abstract: only an SP holding the chunk
   can compute it.

   Time is discrete and passes only while the broker waits for an answer.
   A probe yields a sample (100 = answered correctly within Budget ticks,
   0 = wrong, late or missing) folded into an integer EMA (window W).

   The SP may cheat or fail:
   - DropChunk: deletes a chunk it is paid to keep (AllowDrop).
   - Facade: lacks a chunk but fetches it from another provider (Other) to
     answer the probe; costs RelayLat extra ticks. Caught only if
     MaxLat <= Budget < RelayLat.
   - HeldInit: chunks lost before the period; MaxLat: slow SP.
   - HeldRanges: keeps only these byte ranges of each chunk (partial holder).

   - PartLen > 0: once, the network cuts the SP off for PartLen ticks;
     probes meanwhile time out.

   Period: the broker probes until every chunk was answered (coverage first;
   a failed chunk is probed again) or the nonces or the time are used up,
   then closes the period with
        proof = rep >= Thr /\ probes >= MinProbes /\ every chunk answered.
   The proof is the input of the economic model: payout on TRUE, refund on FALSE.
   An honest SP keeps the proof through a partition if the spare probes
   (Nonces beyond the chunks) absorb the failed ones. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Chunks,    \* chunks the broker knows to be stored
          Ranges,    \* byte ranges
          HeldRanges,\* ranges the SP keeps of each chunk it holds (partial holder if # Ranges)
          Nonces,    \* fresh challenge keys; each is used once (probe budget of the period)
          HeldInit,  \* chunks the SP really holds at start
          AllowDrop, \* the SP may delete chunks (BOOLEAN)
          PartLen,   \* length in ticks of the one network partition; 0 = none
          Other,     \* chunks the SP can fetch from another provider
          RelayLat,  \* ticks to fetch and relay such a chunk
          MaxLat,    \* an SP holding the chunk answers within MaxLat ticks
          Budget,    \* the broker accepts answers up to Budget ticks after the probe
          MaxTime,   \* end of the modelled time
          W,         \* EMA window
          Thr,       \* minimal reputation to get the proof
          MinProbes, \* minimal number of probes in a period to get the proof
          None       \* model value: "no challenge / no response"

ASSUME HeldInit \subseteq Chunks /\ HeldRanges \subseteq Ranges
ASSUME W \in Nat \ {0}
ASSUME Thr \in 0..100
ASSUME AllowDrop \in BOOLEAN
ASSUME Other \subseteq Chunks
ASSUME MinProbes \in Nat
ASSUME PartLen \in Nat

NoChal == None
NoResp == None

Challenge == [chunk : Chunks, range : Ranges, nonce : Nonces]

\* abstract HMAC of a challenge on the chunk data
Hmac(c) == <<c.chunk, c.range, c.nonce>>

VARIABLES held,      \* chunks the SP holds
          chal,      \* open challenge or NoChal
          resp,      \* SP response or NoResp
          used,      \* nonces already spent
          verified,  \* challenges answered correctly and in time
          now,       \* clock
          sent,      \* time the open challenge was sent
          rep,       \* reputation 0..100
          fake,      \* the response was relayed, not computed from own data
          cheated,   \* challenges whose relayed response was accepted
          cut,       \* remaining ticks of the partition: the SP is unreachable
          cutUsed,   \* the partition has happened
          closed,    \* the period is over
          proof      \* the broker's verdict, valid once closed
vars == <<held, chal, resp, used, verified, now, sent, rep, fake, cheated,
          cut, cutUsed, closed, proof>>

TypeOK == /\ held \subseteq Chunks
          /\ chal \in Challenge \cup {NoChal}
          /\ resp \in {Hmac(c) : c \in Challenge} \cup {NoResp}
          /\ used \subseteq Nonces
          /\ verified \subseteq Challenge
          /\ now \in 0..MaxTime
          /\ sent \in 0..MaxTime
          /\ rep \in 0..100
          /\ fake \in BOOLEAN
          /\ cheated \subseteq Challenge
          /\ cut \in 0..PartLen
          /\ cutUsed \in BOOLEAN
          /\ closed \in BOOLEAN
          /\ proof \in BOOLEAN

Init == /\ held = HeldInit
        /\ chal = NoChal
        /\ resp = NoResp
        /\ used = {}
        /\ verified = {}
        /\ now = 0
        /\ sent = 0
        /\ rep = 100
        /\ fake = FALSE
        /\ cheated = {}
        /\ cut = 0
        /\ cutUsed = FALSE
        /\ closed = FALSE
        /\ proof = FALSE

\* integer exponential moving average
Ema(sample) == (rep * (W - 1) + sample) \div W

\* chunks answered correctly and in time
Answered == {v.chunk : v \in verified}

\* the verdict over the period
ProofOK == /\ rep >= Thr
           /\ Cardinality(used) >= MinProbes
           /\ Answered = Chunks

\* broker: probe a chunk with a fresh nonce. Coverage first: a chunk not yet
\* answered is chosen (again) before any answered one. Only if the deadline fits in the model time.
Probe == /\ ~closed /\ chal = NoChal
         /\ now + Budget < MaxTime
         /\ \E c \in Challenge :
              /\ c.nonce \notin used
              /\ c.chunk \in IF Answered = Chunks THEN Chunks ELSE Chunks \ Answered
              /\ chal' = c
              /\ used' = used \cup {c.nonce}
         /\ sent' = now
         /\ UNCHANGED <<held, resp, verified, now, rep, fake, cheated, cut, cutUsed, closed, proof>>

\* the SP can compute the answer from its own data
CanAnswer == chal.chunk \in held /\ chal.range \in HeldRanges

\* SP: can answer only from data it holds
Respond == /\ chal # NoChal /\ resp = NoResp /\ cut = 0
           /\ CanAnswer
           /\ resp' = Hmac(chal)
           /\ UNCHANGED <<held, chal, used, verified, now, sent, rep, fake, cheated,
                          cut, cutUsed, closed, proof>>

\* SP: relay the chunk from another provider
Facade == /\ chal # NoChal /\ resp = NoResp /\ cut = 0
          /\ chal.chunk \notin held /\ chal.chunk \in Other
          /\ now - sent >= RelayLat
          /\ resp' = Hmac(chal) /\ fake' = TRUE
          /\ UNCHANGED <<held, chal, used, verified, now, sent, rep, cheated,
                         cut, cutUsed, closed, proof>>

\* network: the SP becomes unreachable for PartLen ticks (once)
Cut == /\ PartLen > 0 /\ ~cutUsed /\ ~closed
       /\ cut' = PartLen /\ cutUsed' = TRUE
       /\ UNCHANGED <<held, chal, resp, used, verified, now, sent, rep, fake, cheated, closed, proof>>

\* SP: delete a chunk
DropChunk == /\ AllowDrop /\ ~closed
             /\ \E c \in held : held' = held \ {c}
             /\ UNCHANGED <<chal, resp, used, verified, now, sent, rep, fake, cheated,
                            cut, cutUsed, closed, proof>>

\* broker: compare with the HMAC computed on the reference copy
Verify == /\ resp # NoResp
          /\ LET ok == resp = Hmac(chal) /\ now - sent <= Budget
             IN /\ verified' = IF ok THEN verified \cup {chal} ELSE verified
                /\ rep' = Ema(IF ok THEN 100 ELSE 0)
                /\ cheated' = IF ok /\ fake THEN cheated \cup {chal} ELSE cheated
          /\ chal' = NoChal /\ resp' = NoResp /\ fake' = FALSE
          /\ UNCHANGED <<held, used, now, sent, cut, cutUsed, closed, proof>>

\* broker: no answer within the deadline
Timeout == /\ chal # NoChal /\ resp = NoResp
           /\ now - sent > Budget
           /\ rep' = Ema(0)
           /\ chal' = NoChal
           /\ UNCHANGED <<held, resp, used, verified, now, sent, fake, cheated,
                          cut, cutUsed, closed, proof>>

\* time passes while the broker waits; a reachable SP holding the data must
\* answer within MaxLat, and the broker verifies an answer at once
Tick == /\ chal # NoChal /\ resp = NoResp
        /\ now < MaxTime
        /\ ~(CanAnswer /\ now - sent >= MaxLat /\ cut = 0)
        /\ now' = now + 1
        /\ cut' = IF cut > 0 THEN cut - 1 ELSE 0
        /\ UNCHANGED <<held, chal, resp, used, verified, sent, rep, fake, cheated,
                       cutUsed, closed, proof>>

\* broker: no probe left (nonces or time used up): close the period
Close == /\ ~closed /\ chal = NoChal
         /\ used = Nonces \/ now + Budget >= MaxTime
         /\ closed' = TRUE
         /\ proof' = ProofOK
         /\ UNCHANGED <<held, chal, resp, used, verified, now, sent, rep, fake, cheated, cut, cutUsed>>

\* period over (avoids a deadlock report)
Done == closed /\ UNCHANGED vars

Next == Probe \/ Respond \/ Facade \/ Cut \/ DropChunk \/ Verify \/ Timeout \/ Tick \/ Close \/ Done

Spec == Init /\ [][Next]_vars
        /\ WF_vars(Probe) /\ WF_vars(Respond) /\ WF_vars(Facade) /\ WF_vars(Verify)
        /\ WF_vars(Timeout) /\ WF_vars(Tick) /\ WF_vars(Close)

----------------------------------------------------------------------
(* Safety *)
\* the broker never accepts a relayed (facade) response
NoFalseProof == cheated = {}

\* a proof implies every chunk was answered, and by a holder of the data
\* (a drop after the answer is allowed: the proof states the past period)
ProofSound == closed /\ proof => Answered = Chunks /\ cheated = {}

\* reputation above threshold. Holds for a fast SP keeping all chunks.
RepAboveThreshold == rep >= Thr

\* completeness: an honest, fast SP always gets the proof
HonestGetsProof == closed => proof

\* detection: an SP lacking a chunk (lost, or relaying too slowly) never gets the proof
NoProof == closed => ~proof

(* Liveness *)
\* every probe is resolved, also when the SP never answers
Resolved == chal # NoChal ~> chal = NoChal
\* the period ends
Closes == <>closed
=======================================================================
