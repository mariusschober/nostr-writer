# Human Writing Proof — Cryptographic Core 1

**HWP-C/1, publication1.0.0-candidate.1 · 2026-09-15.** An implemented, standards-based positive-proof format with explicit trust, privacy and archival semantics. It does not implement or approve the behavioural detector and does not claim unconditional proof of human cognition.

The core binds an exact UTF-8 document, complete selected-scope map, exact HWP release, exact target captured history, private lineage commitment, required capture/evaluator attestations and optional author association. Nonqualifying input receives no HWP; verification failure never means AI-generated. No real approved HWP release or human-writing certificate is supplied.

## Read and implement

Start with [SPECIFICATION.md](SPECIFICATION.md) and [schema.cddl](schema.cddl). The Python reference is [hwp_crypto.py](hwp_crypto.py); [rfc3161_adapter.py](rfc3161_adapter.py) implements detached timestamp verification. The [security contract](docs/SECURITY.md), [private execution contract](docs/PRIVATE-EXECUTION.md), [HWP-A/0.3 adapter](docs/HWP-A03-BINDING.md), [archival procedure](docs/ARCHIVAL.md), and [Nostr/C2PA/receipt bindings](docs/INTEROP.md) resolve the protocol's interpretation boundaries. [SOURCES.md](SOURCES.md) identifies the primary standards used.

```sh
cd proof/hwp-c-1
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python tools/generate_vectors.py
node tools/independent_check.mjs
python run_checks.py
```

OpenSSL command-line tools are required for timestamp tests; Node is required for the independent interchange checker. One signature test uses the system libsodium shared library. Exact tested versions and every passing test ID are in [vectors/results.json](vectors/results.json). No network service is needed to verify the supplied synthetic fixtures.

## Actual implementation boundary

**Implemented:** deterministic CBOR; COSE_Sign1 Ed25519 with fully specified -19 algorithm; content-addressed bundles; strict signature encoding; salted Merkle root/inclusion/consistency; complete private openings; explicit capture/evaluator/author roles; independently supplied policy and deny lists; passage/whole-document origin checking; exact target and model/release binding; attested and disclosed-recomputation interfaces; detached RFC3161 verification; SHA512 archival inventory; deterministic vectors and negative tests.

**Not claimed implemented:** a trusted native capture path; real HWP model execution (installed callback is deliberately separate); a zero-knowledge proof suite; Nostr/C2PA/OpenTimestamps adapter execution; a complete RFC4998 renewal engine; live revocation or indefinite historical validity. Those boundaries are explicit in the specifications. The completed private mode is attestation-based, not a disguised promise of trustless verification.

The sole signed positive result is `HUMAN-WRITTEN`. Public verification returns `VALID-HWP` with its exact claim/scope/policy, or `NO-VALID-HWP` with no authorship inference. An identified author binding attests a key-controller identity; it does not independently prove which person physically typed. Fresh composition and inherited wording-origin are distinct claims.

## Safe use

The caller supplies the policy and an independently trusted SHA256 pin. Neither the bundle nor a bundled `approved:true` flag grants authority. The command line intentionally requires both:

```sh
python hwp_crypto.py proof.hwp document.txt --policy selected-policy.cbor --policy-pin TRUSTED_SHA256_HEX
```

For disclosed mode or voluntary complete audit, an embedding verifier additionally provides exact private openings, lineage salts and an independently installed release-specific runner. It never executes a bundled program automatically. A fake callback that echoes the statement is not a conforming evaluator.

All private seeds in tests and vectors are deliberately public synthetic keys. All positive fixtures certify only a synthetic test policy/control path, not actual human writing. Never use them for real issuance. The wire-level test bundle is encoded as hex in `vectors/interchange.json`, allowing any language to reconstruct the exact bytes without a binary-file transport requirement.

## Versioning, preservation and licence

The published wire identifier pins this candidate's byte and claim interpretation. Incompatible changes require a new version; model/release changes create new exact manifests. Old proofs retain their original statement, model, scope and trust snapshot. Current trust may change without rewriting historical evidence. The older research and behavioural algorithm directories are not modified.

New original material in this directory is provided under the included MIT licence only. No third-party material is relicensed, no patent assurance is made, and no standards-body adoption or independent security audit is claimed. The standard is open for independent implementation and review; its cryptographic foundation does not itself approve a behavioural detector or capture device.
