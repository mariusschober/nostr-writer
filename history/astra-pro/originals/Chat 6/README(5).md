# WriterFoundation preparation kernels

These pure Swift helpers are deliberately not the application or an HWP verifier. They resolve exact-source coordinate handling, UI projection of verifier outcomes, voluntary-focus state, relay URL identity, NIP-44 length framing and replaceable-event ordering before agents implement platform code.

Run `swift test --package-path mac/Packages/WriterFoundation` from repository root. The preparation environment is Linux Swift 6.2.1; AppKit, signing and native UI tests still require the staged Mac implementation. These functions must not become authority shortcuts: source labels, eligible word roots and verification outputs originate in their independently checked consuming components.

No external dependencies, network calls, cryptographic primitives or bundled font files are included.
