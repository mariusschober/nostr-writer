# Optional interoperability profiles

The authoritative object is the content-addressed HWP-C proof graph. Transport is optional and never supplies behavioural evidence by itself. The following bindings are precise adapter specifications; only core COSE/Merkle and the detached RFC3161 adapter are implemented in this package. No Nostr event, Bitcoin transaction, C2PA credential or public transparency receipt was issued.

## Nostr discovery and version binding

Use standard NIP-01 event verification: exact prescribed event serialization, SHA-256 ID and BIP340 secp256k1 signature. These keys are not Ed25519 keys and their raw secrets/public keys must not be reinterpreted across schemes. Discovery can be an ordinary kind1 event, without claiming an assigned new NIP/kind. Its content may be a human-readable note; machines must not infer authority from prose or an unvalidated tag.

For the experimental machine adapter, content is compact JSON with exactly the ASCII keys `hwp,proof_sha256,package_sha256,document_sha256,article_event,association_sha256`. hwp is `hwp-c/1`; each digest is64 lowercase hex characters; article_event and association_sha256 may be null. Serialize keys in ASCII order with no whitespace; strings have only the indicated ASCII characters. Duplicate keys, unknown keys, invalid digests or noncanonical content reject this adapter. NIP-01 itself signs the event normally; no alternative event-ID formula is introduced.

`proof_sha256` names exact root Proof object CBOR. `package_sha256` names exact `.hwp` file bytes. `document_sha256` must equal the verified statement document digest. To bind NIP-23 content, article_event must name the **exact immutable event ID** and archived event bytes, not only an address/naddr that can resolve to an edited version. Verify that event normally and compare decoded content encoded as UTF-8 byte-for-byte with the HWP document. A title, summary or other article tag is not silently part of the certified body text; certify a separately defined artifact to cover such metadata.

A Nostr key signing that note endorses the association; it is not automatically the HWP author key. For an explicit bidirectional key association, the HWP author additionally signs a COSE object with exactly `{v:"hwp-c/1",type:"nostr-association",proof:Ref,nostr_pubkey:bstr32}`. The author COSE key must be exactly the proof statement's nonnull author. `association_sha256` names that COSE object and the Nostr event's pubkey must equal its nostr_pubkey. Verify both signatures and every equality. This means two keys endorsed one association, not that one identified human exclusively controls both. With a null association field, report only an independent Nostr-key endorsement.

Avoid cycles: create the proof first, then optional author key-association object, then final hosted package, then article/discovery event. If article content depends on proof information, keep that information in external discovery rather than changing already-certified content. Archive all exact event versions and signature objects. Nostr created_at is not a trusted timestamp; a relay does not prove permanent availability or globally unique sessions.

When announcing the actual hosted proof file with NIP-94 kind1063, its `x` is SHA-256 of those exact hosted bytes, and `size` is their byte length. Do not put the root Proof object's digest in `x` unless the served file is exactly that object. Verify the full HWP graph after file retrieval; metadata alone is not a certificate. No relay URL is an essential trust root.

## C2PA asset provenance

A C2PA integration must use the selected C2PA version's manifest, hard binding, signing/credential requirements, assertions and validator. An arbitrary adjacent HWP CBOR file or Ed25519 signature is not by itself a conformant C2PA manifest. A custom assertion should carry exact HWP root/package/document references, claim kind and scope, together with the detached package or its retrievable locator. Until a namespace is registered/agreed, use an explicitly application-scoped experimental label and do not claim standards registration.

The C2PA validator establishes its own signed provenance/binding conclusions; the HWP verifier establishes the HWP result under its external policy. Both must pass for a combined claim. Do not substitute the C2PA issuer for a required HWP evaluator, or infer that C2PA establishes the real-world truth of an arbitrary assertion.

Embedding a manifest changes asset bytes. Use the actual format-specific C2PA hard-binding construction and its defined exclusions rather than attempting to hash a file containing its own final digest. Source Markdown, rendered PDF and a screenshot are distinct assets. A transformed asset must have its own content binding and explicitly retained derivation from the exact certified text; rendering equivalence is outside this core.

## Timestamps and transparent receipts

RFC3161 timestamps attach to the exact finalized `.hwp` file or a specified archival inventory, not to an ambiguous display string. Follow ARCHIVAL.md. OpenTimestamps is an optional alternate prior-existence profile, requiring completed proof and chain validation. RFC9942 COSE receipts can carry a log's inclusion assertion; use that standard's actual proof type, signed checkpoint and verification semantics. A leaf of an HWP private event tree is not automatically a public-log receipt or a Certificate Transparency entry.

Witnessing a root adds evidence about when that commitment existed and consistency with previously seen commitments. It does not prove the underlying events were acquired then, does not rule out unpublished alternative sessions and does not replace the capture/evaluator policy. These adapters add supporting evidence without altering the original HWP-C/1 claim or silently raising its assurance level.
