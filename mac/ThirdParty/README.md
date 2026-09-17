# Locked dependencies

`dependencies.json` records exact upstream commits, purposes, licenses and copied license
hashes. The Xcode workspace lockfile includes the single transitive Swift package,
swift-cmark, also explicitly pinned by WriterExport. No dynamic branch is selected.

ZIPFoundation 0.9.20 is an annotated tag; the manifest pins its peeled commit
`22787ffb59de99e5dc1fbfe80b19c97a904ad48d`, not the tag-object hash.
BigInt supports macOS 10.13+, KeyboardShortcuts 10.15+, CryptoSwift 10.13+,
and ZIPFoundation 10.11+. The selected Swift 6.3 compiler satisfies all manifest
tool versions (the highest is 6.2). Builds verify macOS 14 deployment for the full graph.

The P256K build plugin at its pinned revision was inspected. It invokes `/bin/sh` to copy
`.swift` files from its own `Sources/Shared` to the plugin work directory, without network
or unrelated file access. `verify_build_plugin.py` verifies its hash and rejects any extra
plugin before Xcode's command-line plugin-validation override is used. This is local build
tooling, never app runtime behavior or a production HWP trust exception.

P256K includes vendored libsecp256k1, optional ZKP sources and adapted swift-crypto support;
their notices are retained. Only P256K is linked, not a second secp implementation. No iA
font files or NostrShot source have been copied. Stage 06 records any owner-source adoption
separately from these third-party notices.
