# Developing Nostr Writer

Open `mac/NostrWriter.xcodeproj` and use the shared NostrWriter scheme. The checked-in
project builds without a generator. Regenerate after changing `mac/project.yml` with
XcodeGen 2.46.0: `xcodegen generate --spec mac/project.yml`.

This guide consolidates the former `mac/docs/DEVELOPMENT.md` build/test guidance and
owner-signing instructions. Current acceptance is in the stage ledgers, not in a
build result: Stages 01–02 are recorded as accepted; Stage 03 remains blocked.

## Build and check

Run `mac/scripts/build.sh`, `mac/scripts/test.sh`, and `mac/scripts/check.sh` from
the repository root. Set `DEVELOPER_DIR` only to an installed, compatible Xcode.
The build script produces an ad-hoc-signed development bundle with a separate
container, sandbox and hardened runtime. `CODE_SIGNING_ALLOWED=NO` is suitable for
compile-only CI; it does not verify a signed app's runtime entitlements.

Generated output and dependency checkouts were removed on 30 September 2026. A new
build recreates them and may need network access for the committed dependency pins.
To run the optional protocol suite, recreate `.venv-hwp` using
[the pinned verification instructions](../docs/VERIFICATION.md).

WriterFoundation provides tested contract helpers; WriterStorage implements local
storage, recovery and consented history. WriterHWP, WriterExport and WriterNostr
retain later-stage scaffolding. `hwp-verify --help` describes an eventual interface;
verification exits with unsupported status 69 until Stage 04 implements the protocol.
This is not conformance. Production HWP approvals remain empty.

Native unit tests compile implementation sources into a standalone XCTest bundle,
excluding the executable entry point. UI tests exercise the app. Runtime tests build
for the host architecture; `build.sh` separately builds both distribution architectures.
Debug disables Xcode's optional debug dylib so the ad-hoc executable retains hardened
runtime without a library-validation exception. The non-shipping UI test runner alone
disables hardened runtime so Apple's runner can load its ad-hoc test bundle.

Xcode injects temporary test-manager entitlements into the app under UI test. `test.sh`
isolates those products under `mac/.build/NativeTestDerivedData`; `build.sh` produces
the ordinary app under `mac/DerivedData`. Inspect and launch the ordinary product for
manual acceptance. Test instrumentation is not a distribution artifact. Tests use
synthetic text and development/test identifiers, not user documents or real keys.

## Owner-signed development build

Use an existing Apple Development identity and an owner-selected Apple Developer team.
Configure these in Xcode's account/signing settings before running the helper. Keep
private keys, certificate passwords, recovery keys and account passwords out of prompts
and Git. The owner reviews license agreements and controls provisioning/account changes.

Run `mac/scripts/build_signed_development.sh` with `WRITER_DEVELOPMENT_TEAM` set to the
owner-selected team identifier. The helper refuses a missing/malformed team or a missing
existing Apple Development identity. Xcode selects an existing matching identity; the
resulting signature must report the supplied team. Finish unavailable provisioning in
Xcode before retrying; owner-specific settings are not committed.

The helper builds Debug into `mac/.build/SignedDevelopment`. Its development identifier
and private-store services remain separate from release. It requests one Keychain group
matching the application identifier through Xcode's resolved `AppIdentifierPrefix`;
that prefix is not assumed to equal the current team identifier. See
[Apple's Keychain configuration guidance](https://developer.apple.com/documentation/xcode/configuring-keychain-sharing)
and [the access-group attribute](https://developer.apple.com/documentation/security/ksecattraccessgroup).
The ordinary ad-hoc build uses its own entitlement file and does not claim encrypted
recovery Keychain access; ordinary editing and saving remain available if recovery cannot open.

The helper inspects the actual signature/team, resolved application identity, single
matching Keychain group, sandbox, hardened runtime, allowed entitlements, both CPU
architectures and minimum macOS version. This does not establish live Keychain/provider
behavior, HWP authority, Developer ID distribution or notarization. Use the
[Stage 02](../product/mac/evidence/STAGE-02.md) and
[Stage 03](../product/mac/evidence/STAGE-03.md) reports for recorded observations.

## CI and release

The checked-in native workflow uses a `macos-26` runner and an explicit Xcode 26.6 path.
Its [runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
is a reference; inspect actual availability before changing the workflow. CI has read-only
repository permissions and no signing credentials. Release signing/notarization belongs
to the owner-controlled Stage 08 process.

The manual distribution workflow fails explicitly until Stage 08 supplies `release.sh`.
It names the `macos-release` environment; the owner must configure required reviewers and
signing credentials before distribution. The repository does not establish that these
hosted protections already exist. Pull-request workflows reference no signing secrets.
