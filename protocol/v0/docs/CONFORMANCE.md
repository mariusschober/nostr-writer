# Conformance classes, vectors, implementation rules and freeze

## Classes and required behaviour

**P — producer/evaluator.** Produces canonical v0 observations, commitments and positive appraisals from actual `hwp-a/v0` execution; validates scope/target/lineage; refuses negative or incomplete results. This class does not by itself establish authority to observe or certify. A native capture implementation additionally needs evaluated admission for its claimed path. The supplied fixture builder is a test generator, not a native recorder.

**V — public attestation verifier.** Implements the complete canonical-object, signature, role, authority, definition/release, prospective capture-plan, exact final document, dependency graph, scope, parent proof and author checks for attested-v1. It must explicitly reject a statement requiring disclosed-v1 when it does not implement R; it may not downgrade it to public attestation. The supplied independently written JavaScript verifier implements V.

**R — recomputing verifier.** Implements V and complete private disclosure opening, canonical record reconstruction, actual behavioural replay/features/model/support/aggregation, exact source-root mapping, private lineage output and statement equality. It supports mandatory disclosed-v1 and voluntary full audit of attested-v1. The supplied Python verifier implements R with a closed installed bridge, not a generic caller callback.

**T — supplemental timestamp verifier.** Checks RFC3161 token binding under separately selected authorities, policy OIDs, validation time and optional nonce. It must report unassessed revocation and must not turn a timestamp into a human-composition or exact writing-time assertion. It is not a substitute for V or R. The supplied Python/OpenSSL adapter implements the stated subset.

Every class must preserve the claim kind, selected/whole distinction, test-only projection, no-negative-authorship semantics, immutable release interpretation and resource limits. A producer or verifier cannot authorize itself by shipping a policy beside a bundle. Independent applications can supply different externally selected policies; conformance compares equal policy inputs, not globally uniform trust decisions.

## Normative test material

`vectors/interchange.json` is the deterministic, public-keyed interchange set. Its object pool maps SHA-256 hex to exact bytes encoded as hex. Each case references a proof bundle, exact document, external synthetic policy, private ABI disclosure and expected semantic projection. Expected public and R outcomes are recorded separately. Class-V cases requiring disclosed mode explicitly expect rejection for lack of required recomputation.

The ladder contains exact signed capture refs, count/root, selected salted leaf openings and inclusion paths, a complete normalized record, exact private lineage bytes and expected computed statement bindings. It allows an independent implementation to locate the first disagreement: wire decoding → captured event root → normalized record → algorithm output → lineage commitment → statement/appraisal. All salts and private keys are intentionally public test material. They must not be used for live signing.

`vectors/algorithm-feature-vector.json` provides the complete179-feature integer output for the inherited baseline fixture. `docs/FEATURE_NAMES.json` supplies the normative order. The algorithm and integration tests cover exact replay, Unicode, input profiles, causal attribution, origin history, source chronology, scope, model validation/fitting/export, domain/support, complete trial accounting, statistical eligibility and feature collision. Timestamp tests use temporary local synthetic CA/TSA keys; they are not public notarizations.

Independent test comparison must include malformed/noncanonical CBOR, every rejected unknown field and mode, wrong refs/size, wrong document/newline/normalization, duplicate/quorum/role keys, stripped author association, target confusion, changed prospective release, parent substitution, partial disclosure, reordered/changed openings, salt mismatch and the authorized-lying-attestor boundary. A parser accepting generic CBOR tag18 with a non-COSE value is not itself wrong; signature validation must reject that value. Syntax conformance and semantic object conformance are separate.

Successful V/R results must agree on exact document/proof/release identities, claim, selected intervals, optional author association and test-vs-production projection. Attestation and recomputation must report their different execution basis. Failure reason wording and UI presentation are not conformance identities. No writing interface is specified here.

## Reproduce locally

From `protocol/v0`:

```
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python run_checks.py
node tools/check_interop.mjs
python tools/check_freeze.py
```

The exact environment and test IDs are in `vectors/results.json`. No service or company infrastructure is used by these tests. Deterministic vectors must regenerate identically in fresh processes and under different PYTHONHASHSEED settings. Model fitting is only environment-reproducible; the exact exported model, not arbitrary future refits, defines the inference. Timestamp tests generate new temporary keys and time evidence and are not byte-reproducible; their validation outcomes are checked separately.

The definition/program manifests already exist in a frozen distribution. `tools/build_manifests.py` is a **pre-freeze maintainer tool**, never a verifier repair step. Running it after changing code creates a different interpretation hash and invalidates the recorded freeze, even when the human-readable version name was not changed. `tools/check_freeze.py` detects changes without rebuilding or authorizing anything.

## Freezing and independent engineering

A freeze comprises exact normative bytes, source/reference computation, schemas, vectors, tests, dependency/environment declarations and a SHA-256 inventory. The protocol-definition identity excludes vectors and result inventories to avoid self-reference; the final freeze inventory then binds them along with the definition. Git tags and hosting URLs are convenient labels, not the source of the mathematical identity. A signed/reviewed release can independently endorse that identity later; this package does not manufacture such third-party review.

The Python reference's portable manifest identifies the function to compute, not the only permitted implementation language. Independent engineers may reproduce it from the complete state transitions, integer formulas, ordered feature list and schemas. They must preserve all consequential comparisons, iteration ordering and bounds. Native machine binary hashes and transitive runtime security belong to each admitted deployment profile; hashing Python source does not prove a protected native input path.

Unknown empirical weights are not an underspecified default: no production weights are supplied. The model artifact's precise schema, fitting/export procedure and runtime decision are fixed. Researchers can train and evaluate new exact models under the unchanged contract. No guessed threshold, placeholder neural component or unavailable ZK prover can fill the absence of a qualified release.

The freeze does not require accepting a known-bad empirical model. It freezes the falsifiable inference procedure and the obligations a future model/capture release must satisfy, while keeping the production approval set empty. At least one conformance execution in every claimed input profile and each supported claim/mode must run through the real bridge before a reference release is considered complete.
