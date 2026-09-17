# Exact assessment, lineage and public result contract

## Successful algorithm assessment

The algorithm release returns the following exact map for a well-formed scored input:

```
{
 verdict:"HUMAN-WRITTEN"|"NOT PROVABLE",
 contribution_verdict:"HUMAN-WRITTEN"|"NOT PROVABLE",
 ranges:[{
   start:uint, end:uint,
   verdict:"HUMAN-WRITTEN"|"NOT PROVABLE",
   excluded:bool, exclusion:uint|null,
   reason:text|null,
   origin:"direct"|"inherited"|"external"|"spelling",
   origin_documents:[text,...]
 }],
 reason:null,
 candidate_document_pass:bool,
 certification_enabled:bool,
 claim_kind:"fresh-composition"|"wording-origin",
 algorithm_version:"hwp-a/v0"
}
```

Ranges cover exact UTF-8 byte intervals and coalesce adjacent equal algorithm metadata. This **algorithm range partition** differs from the maximal public proof-origin partition: neither is silently substituted for the other. Origin-document IDs follow the reference's sorted original-home set. Exclusion indices refer to the ordered requested exclusion list. A range that is excluded can still have a positive underlying contextual score; exclusion is a claim decision, not an allegation about its origin.

The complete returned assessment is canonical-CBOR encoded. Runtime duration, floating-point measurements of performance, memory addresses, platform exception strings and environment-specific representations are not included. A malformed or unsupported record produces no positive private lineage. Negative error diagnostics need not be committed or published; no negative authorship certificate is issued.

`candidate_document_pass` is diagnostic, not an alternative acceptance route. `certification_enabled` is populated only from authenticated bridge admission, not submitted telemetry. For conformance fixtures the internal algorithm can return a conditional positive, but the public policy projection must remain NOT PROVABLE.

## Private lineage object

```
{
 adapter:"hwp-a-v0-output/1",
 target_record_id:text,
 record_captures:[{id:text,capture:Ref},...],
 assessment:exact_complete_assessment_above
}
```

Record order is the fixed dependency-ready UTF-8 topological order. Its commitment uses the exact CBOR bytes and a private independent32-byte salt. The private map does not contain its final statement Ref, so it has no hash cycle. It commits the algorithm's interpreted provenance and scope result; raw observations are separately committed in the capture Merkle trees. A compact selected-range summary cannot replace this object.

## Public verification projection

The public normative outcome is HUMAN-WRITTEN or NOT PROVABLE. A conforming successful production result additionally communicates exact protocol, claim, whole/selected scope, selected intervals, document Ref, proof Ref, release Ref, trust-policy digest, execution mode and optional author association. Its `execution_checked` is `attestation` or `recomputed` and cannot be omitted in a description that would imply the latter. Policy status_as_of is a declared assessment reference, not a trusted timestamp. Timestamp evidence is separately assessed.

The reference's successful result map includes `status`, `outcome`, `result`, `claim`, `scope`, `ranges`, `proof`, `document`, `release`, `mode`, `policy_sha256`, `policy_status_as_of`, `author`, `timestamp:"not-assessed"`, `execution_checked`, `test_conformance`, `protocol`, `authorship_inference:null`. A TEST-ONLY result sets outcome NOT PROVABLE, result null and test_conformance true. Failure sets status NO-VALID-HWP, outcome NOT PROVABLE, protocol hwp/0, a diagnostic reason and authorship_inference null. No missing proof is called AI-written.

Independent implementations must agree on the outcome and successful semantic content, not necessarily wording of rejection reasons or formatting of optional diagnostics. Ref bytes in diagnostic JSON use lowercase hex; this JSON is not the signed format. The JavaScript class-V reference returns a smaller successful diagnostic map and the same normative semantic fields. Its inability to execute disclosed mode is explicit non-support, never a weaker positive.

## Installed interfaces

`protocol.verify(bundle_bytes, exact_document_bytes, policy_bytes, policy_pin, disclosures=None, recompute=False)` performs the full public checks. It has no arbitrary-runner argument. `disclosure.pack/unpack` supplies the portable private bundle representation. `protocol.evaluate_statement` recomputes an issuance proposal from complete authenticated openings. `protocol.issue_appraisal` repeats that evaluation and returns a positive signature only after exact result equality and signer authorization. Low-level signing primitives are not an alternate protocol issuance path.

The executable CLI is `python -m hwp0 proof.hwp document.txt --policy selected.cbor --policy-pin HEX [--disclosure private.hwp] [--recompute]`. Exit0 is a production positive, exit2 is conformance-only, exit1 is no valid proof. No conformance example exits0. The JavaScript V CLI similarly distinguishes TEST-ONLY and refuses mandatory recomputation.

The reference source validates its pinned installation before evaluating. Operational faults, unavailable local files or exhausted runtime resources are not positive results. Experimental tools must distinguish such incomplete runs from fully observed rejected attacks instead of using implementation failures to improve their measured risk.
