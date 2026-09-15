# Primary standards and evidence boundaries

Checked 2026-09-15. HWP-specific objects, roles, scope semantics and adapter choices are new specifications in this package; publication does not imply IETF, Nostr or C2PA approval. No source supplies measured HWP accuracy.

| Source | Use and limit |
|---|---|
| [RFC8949](https://www.rfc-editor.org/rfc/rfc8949.html), §4.2.1 | Core deterministic CBOR bytewise encoded-key order, not the separate length-first option |
| [RFC9052](https://www.rfc-editor.org/rfc/rfc9052.html) | COSE_Sign1, protected headers, external AAD and Sig_structure; HWP fixes a strict subset |
| [RFC9864](https://www.rfc-editor.org/rfc/rfc9864.html), October2025 | Fully specified COSE Ed25519 identifier -19; do not infer current registries from old -8 examples |
| [RFC8032](https://www.rfc-editor.org/rfc/rfc8032.html) | Ed25519 and published test vector; HWP specifies stricter accepted public-point encodings |
| [RFC9162](https://www.rfc-editor.org/rfc/rfc9162.html) | Ordered Merkle shape, inclusion and consistency; HWP leaves are its own salted profile, not CT certificates |
| [RFC9334](https://www.rfc-editor.org/rfc/rfc9334.html) | Separation of attestation evidence, appraisal and relying-party trust |
| [RFC3161](https://www.rfc-editor.org/rfc/rfc3161.html) | Timestamp token structure and message-imprint binding; not composition evidence |
| [RFC4998](https://www.rfc-editor.org/rfc/rfc4998.html) | Archival evidence renewal; the included inventory is not a complete ERS engine |
| [RFC9942](https://www.rfc-editor.org/rfc/rfc9942.html), June2026 | Standard COSE receipts for optional transparency integration, not human-writing certification |
| [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md), [NIP-23](https://github.com/nostr-protocol/nips/blob/master/23.md), [NIP-94](https://github.com/nostr-protocol/nips/blob/master/94.md) | Event signatures, exact long-form version and hosted-file hash respectively |
| [C2PA2.4 specification](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html) | Optional asset-provenance integration, requiring its own conformant manifest and trust checks |
| [OpenTimestamps](https://opentimestamps.org/) | Optional decentralized prior-existence evidence; full final proof and accepted chain required |
| [RISC Zero documentation](https://dev.risczero.com/) | Example of publicly verifiable program execution; no HWP guest/prover suite is implemented or approved here |

The cryptographic reference, attack tests, vectors and interface choices are original work for this request. Standard names are not a substitute for independent security review. Additional third-party implementations used by tests retain their own licences. No new patent or standards-governance commitments are implied by this package.
