# Primary standards and provenance of this work

Reviewed 15 September2026. These sources support the cryptographic and attestation mechanisms, not HWP human-writing accuracy. The protocol's integration fixes and executed regressions are original work in this package, based on the preserved input archives identified in `baseline/INPUTS.json`.

- RFC8949, §4.2.1: core deterministic CBOR, not length-first map sorting. https://www.rfc-editor.org/rfc/rfc8949.html
- RFC9052: COSE structures and signature context. https://www.rfc-editor.org/rfc/rfc9052.html
- RFC9864: fully specified Ed25519 COSE algorithm−19. https://www.rfc-editor.org/rfc/rfc9864.html
- RFC8032: Ed25519 and known-answer vectors. The v0 strict subgroup/encoding acceptance profile is explicitly additional. https://www.rfc-editor.org/rfc/rfc8032.html
- RFC9162, §2.1: ordered Merkle tree shape and inclusion/consistency. HWP salts and leaf domains are its own profile; this is not a Certificate Transparency deployment. https://www.rfc-editor.org/rfc/rfc9162.html
- RFC9334: roles and trust relationships in remote attestation; evidence and appraisal do not authenticate themselves. https://www.rfc-editor.org/rfc/rfc9334.html
- RFC3161: timestamp token structure and prior-existence attestation. https://www.rfc-editor.org/rfc/rfc3161.html
- RFC4998: long-term evidence-record renewal concepts. The package's archive inventory is not a complete ERS implementation. https://www.rfc-editor.org/rfc/rfc4998.html

The preserved A03 theory/data documents identify their primary statistical and input-method sources. No third-party study result is substituted for missing HWP participant data. Exact ordinary equivalence/union-bound/binomial deductions are presented with their assumptions rather than attributed a new empirical significance.
