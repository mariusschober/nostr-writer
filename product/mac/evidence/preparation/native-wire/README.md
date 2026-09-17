# Native wire primitives — independent preparation

This work is on the local, unmerged `preparation/native-cores` branch. Stage 01
acceptance is still blocked. This is not Stage 04 acceptance, a working HWP producer,
or an actual human-writing certificate. No acceptance requirement is removed.

Prepared native code implements the frozen restricted canonical CBOR domain,
content-addressed object storage, COSE Sign1 with Ed25519 (-19), strict public point
and signature scalar checks, salted event leaves, Merkle roots/inclusion/consistency,
and lineage commitments. All 17 tests passed on the same Mac/toolchain recorded in
Stage 01. The subsequent two affected fixture-loading tests passed after replacing
the duplicate 15 MB vector with an in-place frozen file read and SHA-256 check.

Evidence includes 61 CBOR wire cases; all 45 distinct signatures extracted from frozen
bundles; 30 public-point vectors; exact frozen bundle byte round trips; prefix roots;
consistency paths; four salted capture openings; and substitution/truncation/resource
boundary tests. Production admission, replay/features/model/support/aggregation,
capture/disclosure reconstruction, policy/authority/role/parent/author checks, actual
P/V/R composition, CLI verification, proof UI and empirical accuracy remain unimplemented
or unmeasured. The existing CLI still explicitly reports unsupported verification.

Private signing remains CryptoKit. Apple deliberately randomizes Ed25519 signatures:
[signature(for:)](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey/signature(for:)).
The initial test assumption that two implementations must emit identical signature
bytes was false on this platform. Exact keys, protected headers and payload bytes
match; all frozen signatures verify natively, and the frozen Python verifier accepts
native signatures. `signing-cross-check.json` records that independent result.
No alternate private signing primitive was added, and no frozen signature, equation,
point/scalar check or protocol file was changed. Future issuance must persist the exact
signed object once; regenerating a signature creates different object bytes.

Swift map values preserve byte-distinct UTF-8 keys and semantic map equality, independent
of insertion order. Canonical encoded order remains bytewise, including mixed positive/
negative integer keys. The parser enforces depth/item/byte limits and cancellation.
The native store also limits aggregate resident object bytes to 64 MiB; this is a
conservative local resource bound, not a different accepting protocol computation.

The fixtures contain only public synthetic conformance keys/material and belong to the
test target. They are never app resources or production trust. `generate_test_oracles.py`
first verifies the frozen inventory, then writes only the native test fixtures. It
does not run a manifest builder, generate replacement frozen vectors, or modify v0.

Commands executed in the isolated preparation workspace:

```sh
swift test --package-path /private/tmp/nostr-writer-hwp-core/Packages/WriterHWP --scratch-path /private/tmp/nostr-writer-hwp-core/build
HWP_PROTOCOL_ROOT='/Users/schober/Projects/Nostr Writer/protocol/v0' swift test --package-path /private/tmp/nostr-writer-hwp-core/Packages/WriterHWP --scratch-path /private/tmp/nostr-writer-hwp-core/build --filter 'testFrozenVectorAndObjectPool|testFrozenBundlesRoundTrip'
```

The two fixture-loading checks also passed without an environment override in the
actual repository layout (`repository-layout-tests.log`).

For the repository layout, run `swift test --package-path mac/Packages/WriterHWP`.
Tests locate `protocol/v0` relative to their source; `HWP_PROTOCOL_ROOT` is only needed
when running a standalone copied package. Set `HWP_NATIVE_SIGNATURE_OUTPUT` to an
explicit synthetic-output path to export the public signing sample for Python checking.
File hashes in `source-files.json` identify the reviewed copied sources. Test logs are
kept verbatim. The code has not yet been accepted into the application stage sequence.
