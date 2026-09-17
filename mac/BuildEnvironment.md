# Stage 01 build environment

Observed 17 September 2026 on Apple silicon (arm64): macOS 26.6.2 (25G83),
Xcode 26.6 (17F113), macOS SDK 26.5, Apple Swift 6.3.3.
Explicit developer directory: `/Applications/Xcode.app/Contents/Developer`.
Project generator: XcodeGen 2.46.0. The generated project and shared scheme are checked in;
XcodeGen is not required to build a clone.

Stage 01 resolves the recovered toolchain mismatch by using this installed, supported
Xcode for implementation. Apple lists Swift 6 language mode and macOS 14 deployment
within [Xcode 26.6's supported range](https://developer.apple.com/xcode/system-requirements).
This does not claim an Xcode 27 run. The app targets macOS 14.0 with complete Swift 6
concurrency checks, arm64 and x86_64. Intel and macOS 14 runtime coverage remain unmeasured.

Debug uses `com.mariusschober.nostrwriter.development`; Release uses
`com.mariusschober.nostrwriter`. UI/unit test bundles have separate suffixes. Tests use
synthetic inputs and isolated defaults. No production Keychain identity was accessed.
The host currently reports zero valid code-signing identities; local builds use ad-hoc
signing, which is not Developer ID signing or notarization.

Runtime does not invoke Python or Node. The separately installed repository-local
Python environment and OpenSSL 3 are conformance oracles only.
