# Developing Nostr Writer

Open `mac/NostrWriter.xcodeproj` and use the shared NostrWriter scheme. The checked-in
project builds without a generator. To regenerate after changing `mac/project.yml`,
use XcodeGen 2.46.0: `xcodegen generate --spec mac/project.yml`.

Run `mac/scripts/build.sh`, `mac/scripts/test.sh`, and `mac/scripts/check.sh` from
the repository root. Set `DEVELOPER_DIR` only to an installed, compatible Xcode.
The build script defaults to an ad-hoc-signed development bundle with a separate
container. `CODE_SIGNING_ALLOWED=NO` is appropriate for compile-only CI, not an
assertion that sandbox entitlements have been verified in a running signed bundle.

The Foundation package supplies the new, tested contract helpers. Other local packages
have no working public surface until their respective stages. `hwp-verify --help`
describes the eventual interface; verification exits with unsupported status 69 until
Stage 04 implements the actual protocol. This must not be counted as conformance.

The Stage 01 editor is a scratch adapter, with explicit basic file save and no autosave
or capture storage. Recording consent is stored separately from every future publishing
decision. Tests operate on synthetic text and development/test identifiers. No release
build accepts a test policy as production trust. The frozen production approval set
remains empty.

Native unit tests compile the app's implementation sources into a standalone XCTest
bundle, excluding its executable entry point. This avoids injecting an ad-hoc test
bundle into the hardened application, which requires a matching signing team. UI tests
exercise the actual app. Runtime tests compile for the host architecture; `build.sh`
separately compiles both distribution architectures. Debug disables Xcode's optional
debug dylib so its ad-hoc executable can retain hardened runtime without a library
validation exception. No product sandbox or hardened-runtime entitlement is relaxed.
The separate, non-shipping UI test runner does not enable hardened runtime: Apple's
runner dynamically loads its ad-hoc test bundle. This override is scoped to the
`NostrWriterUITests` target and does not change the application target's signing flags.
Xcode also injects temporary test-manager entitlements into the app under UI test.
`test.sh` isolates these products under `.build/NativeTestDerivedData`; `build.sh`
produces the ordinary app under `DerivedData`. Inspect and manually launch that
ordinary product for the least-privilege acceptance check. Test instrumentation is
never a distribution artifact.

Hosted CI is separate from local execution. It uses the available `macos-26` runner and
an explicit Xcode 26.6 path documented in the
[runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
It receives read-only repository permissions and no signing credentials. Distribution
signing/notarization requires the separate owner-controlled release process in Stage 08.
The manual distribution workflow currently fails explicitly until Stage 08 supplies
`release.sh`. It names the `macos-release` environment; the owner must configure required
reviewers and signing credentials there before distribution is enabled. This repository
does not assert that those hosted environment protections already exist. No signing
secrets are referenced by pull-request workflows.
