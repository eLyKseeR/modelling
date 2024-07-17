(** 
 LXR - eLyKseeR data archive
 *)

(**
 Module: Assembly
 Description: an assembly is an ordering of chunks of data,
              either plain for reading and writing, 
              or encrypted for longterm storage.
 *)

(** we build on the _ssreflect_ *)
From Coq Require Import ssreflect ssrfun ssrbool.
Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

From Coq Require Import Strings.String Strings.Byte Lia.

From CoLoR Require Import Util.Matrix.Matrix.
From CoLoR Require Import Util.Vector.VecUtil.

(** constants *)
Section Constants.

(** chunk 2D size *)
Definition chunkwidth : nat := 256.
Definition chunklength : nat := 1024.

(** assembly size range (count of chunks) *)
Definition assemblyminsz : nat := 16.
Definition assemblymaxsz : nat := 256.

End Constants.

Section Data.

(** data structures *)

Import BigNMatrix.

Definition valid_assembly_size (n : nat) : Prop :=
    n >= assemblyminsz /\ n <= assemblymaxsz.

Lemma invalid_assembly_low : forall n, n < assemblyminsz /\ valid_assembly_size n -> False.
Proof.
    intros n. unfold valid_assembly_size.
    unfold assemblyminsz. unfold assemblymaxsz.
    lia.
Qed.
Lemma invalid_assembly_hi : forall n, n > assemblymaxsz /\ valid_assembly_size n -> False.
Proof.
    intros n. unfold valid_assembly_size.
    unfold assemblyminsz. unfold assemblymaxsz.
    lia.
Qed.

(** encrypted data can be extracted as chunks *)
Record chunk : Type := mkchunk
    { id : nat
    ; buffer : matrix chunkwidth chunklength
    }.

(** the ordered set of chunks is an assembly *)
Record assembly (n : nat (*| n >= assemblyminsz /\ n <= assemblymaxsz*)) : Type := mkassembly
    { n : nat
    ; valid : Prop
    ; apos : nat
    ; encrypted : bool
    ; chunks : vector chunk n
    }.
(* Print assembly. *)
(* Check apos. *)

Definition new_chunk (id : nat) : chunk :=
    mkchunk id (zero_matrix chunkwidth chunklength).
(* Print new_chunk. *)

(** create assembly (count of chunks) *)
Program Definition new_assembly (n : nat (*| n >= assemblyminsz /\ n <= assemblymaxsz*)) : assembly n :=
    mkassembly n
               (valid_assembly_size n)
               0
               false
               (Vbuild (fun i (ip : i < n) => new_chunk i)).
(* Print new_assembly. *)

Lemma valid_assembly_20 : let a := new_assembly 20 in valid a.
Proof.
    unfold new_assembly. simpl. unfold valid_assembly_size.
    split.
    - unfold assemblyminsz. lia.
    - unfold assemblymaxsz. lia.
Qed.

(** an experiment to have the size checked on creation.
    there is a problem that the size now needs to be set
    via a theorem. (see Theorem valid_assembly_size_20)      *)

Program Definition create_assembly (n : nat) (_ : valid_assembly_size n)
    : assembly n :=
    (* : {a : assembly n | valid_assembly_size n} := *)
    mkassembly n
               (valid_assembly_size n)
               0
               false
               (Vbuild (fun i (ip : i < n) => new_chunk i)).
Print create_assembly.

(* Theorem valid_assembly_size_20 : valid_assembly_size 20.
Proof. unfold valid_assembly_size. unfold assemblyminsz. unfold assemblymaxsz. lia. Qed.
Lemma create_assembly_20 : let a := create_assembly valid_assembly_size_20 in valid a.
Proof.
    unfold new_assembly. simpl. unfold valid_assembly_size.
    split.
    - unfold assemblyminsz. lia.
    - unfold assemblymaxsz. lia.
Qed. *)

End Data.

(** The work is managed as a list of actions.
    With a smart idea, disjointness of actions, we can split this list into sublists
    and apply it by a set of threads concurrently. *)

(** Example: read "bunch" of 256 bytes from a file and store in assembly
             by distributing over its 16 chunks.
    
    Fixpoint add_data (d : bunch) (i : nat) (nc : nat): list action :=
        match d with
        | [] => []
        | h :: t => AppendAction (i % nc) h :: add_data t (i + 1) 
        end.
    
    (* create list of pairs of chunk id * position in chunk *)
    Fixpoint apply_actions (a : list action) : list (cid, idx) :=
        ...

    (* proof that there are no two equal pairs in the list of actions *)
    Theorem add_data_disjoint : let d := test_bunch in 
                                let as := apply_actions(add_data d) in
                                length as = length(disjoint_pairs as).
      *)
Section Access.
(** Reading from and writing to an assembly
    and the underlying chunks *)


End Access.

Section Extraction.
(** Encryption and extraction of chunks to files *)


End Extraction.

Section Reconstitution.
(** Reconstituion of chunks from files and their decryption *)


End Reconstitution.
