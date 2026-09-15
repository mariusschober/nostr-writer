# HWP-A/0.3 evidence and output binding profile

This document fixes the crypto adapter's interpretation of the existing HWP-A/0.3 contract. It does **not** change replay, features, thresholds, model fitting or HWP decisions. A conforming algorithm implementation and approved release remain separate dependencies. This profile is a normative adapter specification, not a claim that the local cryptographic fixture runner implements HWP-A.

## Captured event representation

Each admitted capture corresponds to exactly one complete HWP record. Canonical CBOR represents existing JSON null/Boolean/string/array/map/safe-integer values without Unicode normalization. All JSON keys remain text. Reject floats, duplicate keys, lone surrogates and unsafe integers before conversion. No `seq`, `delivery`, input source or missing event may be invented to upgrade an old trace.

The first committed event has exactly:

`{kind:"header", adapter:"hwp-a03-cbor/1", id:text, language:text, resolution_us:uint, paths:map}`.

These are the original record metadata. Intermediate events have exactly `{kind:"observation",value:original_observation}` or `{kind:"transaction",value:original_transaction}`. They appear in the original combined contiguous `seq` order, beginning at0. The outer header and terminal do not consume HWP `seq` values. The last event has exactly `{kind:"end",final_text:original_final_text}`. A native normalizer must commit each observed event as acquired; retrospective wrapping alone does not establish authenticity.

The decoder restores `observations` and `transactions` by filtering this one sequence, preserves original `i` values, and constructs the exact existing record fields `id,language,resolution_us,paths,observations,transactions,final_text`. Unknown wrapper fields or an HWP value failing its native parser reject. Header/end markers within intermediate positions are prohibited. `count` is therefore `len(observations)+len(transactions)+2`.

## Multiple records and target

Map each unique record ID to one exact capture-end Ref. Two captures with the same record ID reject, even if their final text matches. Select the target ONLY using statement.target_capture. Every external `copy.from_doc` creates a dependency on that record's capture. Include exactly the target and its transitive record dependencies; unknown dependencies, unrelated extras or cycles reject. This prevents an evaluator from choosing favourable collateral histories.

Construct the HWP bundle's documents by Kahn topological sorting of these dependencies; among currently available nodes choose the smallest UTF-8 encoded record ID in unsigned bytewise order. Internal copies from the same record do not create an inter-record edge. Set bundle.version=`hwp-a/0.3` and bundle.target to the selected target's original ID. This fixes crypto-adapter input ordering without changing within-record HWP semantics. Native multi-device fragments that are not complete valid HWP records need a future capture/algorithm profile; do not concatenate them by invented timestamps.

## Exact release inputs and installed execution

The algorithm-spec, program and model objects, exact decision policy, this evidence adapter and the output contract are all distinct release artifact Refs. The decision-policy artifact for this adapter is canonical CBOR with exactly `{threshold:int,claim_kind:"fresh-composition"|"wording-origin",allowed_domains:[text,...]}`; allowed_domains is sorted, unique and nonempty using UTF-8 order. It contains no `approved:true` authority.

The relying party installs and independently approves the exact compatible HWP executable and full transitive dependencies. Program artifact should be a content-addressed build/dependency manifest; its native format and closure validation must be part of the release's approved build profile. Core HWP-C authenticates artifact bytes but does not execute or parse arbitrary build manifests. No remotely downloaded executable may be loaded merely because its hash matches a bundle reference.

For each capture, the installed bridge obtains the observed record and constructs HWP's independently supplied context from the admitted capture decision, exact record snapshot, release model, threshold, allowed path domains and claim. `fresh_record_ids` here means admitted to this original captured execution, not 'never verified before'. Re-verification of the original statement is permitted. This context must not be populated solely from author assertions or the fixture helper.

## Scope and exact private output

The public scope is requested before computation. Convert its excluded byte intervals and reasons to the existing HWP `excluded` input; all HWP segmentation and underlying scores remain independent of these exclusions. Run the exact release. Require the actual whole-document or selected-contribution HWP verdict to be HUMAN-WRITTEN, appropriate to the public scope kind. Every selected scalar must actually have a positive HWP range. A subset cannot be called a whole-document result.

This adapter's private lineage-output byte string is canonical CBOR of:

`{adapter:"hwp-a03-output/1",target_record_id:text,record_captures:[{id:text,capture:Ref},...],assessment:map}`.

`record_captures` follows the deterministic topological record order. `assessment` is the complete normative HWP verification result map returned by the independently installed release entry point, before presentation formatting, not an invented lower-resolution summary. Its field names, allowed values and exact internal meaning are fixed by the pinned algorithm specification and output contract. It must contain no runtime timing, platform-specific object representation, random diagnostics or unversioned library messages. A release whose HWP result contains such unstable fields is not compatible until its explicit output contract defines a deterministic exported assessment; that export becomes part of the approved computation, not discretionary filtering at verification time.

The bridge must also independently check its replayed origin graph against each selected public origin. `observed` dependencies are the sorted capture Refs of all records actually required for that range under HWP's lineage, not merely the target's recorder. The subjects of selected fresh observed origins must equal statement.author (including null). `inherited` refers only to a separately verified positive parent proof with literal covered bytes; it never certifies the new assembler's composition. The crypto verifier checks parent authenticity and byte coverage, while the installed bridge confirms that this parent is the actual source represented by the captured copy operation. A new parent mapping needs a new assessment, not a UI annotation.

Compute lineage=SHA256(CBOR(["HWP-C/1:lineage", provided_salt32, exact_lineage_output_bytes])). Compute the exact raw UTF-8 document Ref, canonical public scope Ref and release Ref. Return exactly `{document,scope,lineage,release,captures,target_capture,result:"HUMAN-WRITTEN"}`. This output must be recomputed from captured inputs and the approved release, never copied from a statement merely to make signature checks pass.

## Reproducibility boundary

The crypto package exercises this callback ABI using explicitly synthetic fixtures. It does not execute the actual HWP-A algorithm or approve it. Independent engineers can implement this bridge against the retained exact HWP-A release without changing the cryptographic core. Older A1/0.2 records or a future 0.4 algorithm require different adapter/release identities. A capture-record hash alone does not identify an execution target, and a statement's model name alone does not identify its computation.
