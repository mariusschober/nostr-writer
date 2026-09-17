# Stage 01 — native foundation (acceptance blocked)

Stage 01 is **not accepted**. This is a live implementation report, not a substitute
for the frozen acceptance matrix. Machine-readable status is in `STAGE-01.json`.
Input: `3fdab5b1f8d75720c3025e8604f947e2307c31e2`. Source candidate: `5024c1cb9924db8980e55d26ce0dbd33fdf366b9` on
`implementation/stage-01`. Evidence is committed separately so it can name the exact
source commit without a self-referential hash.

## Implemented scope

The missing WriterFoundation is new implementation from current recovered contracts:
exact UTF-8 snapshots/UTF-16 scalar coordinates, proof presentation conditioned on an
independently selected policy, relay URL identity, checked extended NIP-44 framing,
replaceable-event ordering and a pure focus reducer. None is a
replacement for Stage 04's native HWP algorithm, producer or verifiers. The historical
47-test result is not applied to this code.

The checked-in Xcode project builds a regular NSDocument app with AppKit lifecycle,
TextKit 2 scratch editing, SwiftUI sidebar/settings, recording consent, native menus
and explicit unavailable controls for later capabilities. Package scaffolds, exact
dependency pins/licenses, shared protocols, scripts and separate CI/release workflows
are present. The native `hwp-verify` interface builds; actual verification exits 69
with an explicit unsupported explanation until Stage 04.

The scratch editor is not Stage 02 persistence or Stage 03 capture. No detailed history,
Nostr network client, HWP issuance, export renderer or focus adapter is claimed present.
The production approval set remains empty. All historical and protocol originals are
unchanged. The original preparation package README remains historical provenance;
current implementation guidance is in `mac/docs/DEVELOPMENT.md`.

## Verification and acceptance

| ID | Current result | Evidence |
| --- | --- | --- |
| M01 | PASS: 178 current frozen tests, independent checker, deterministic vectors and freeze checks | `logs/stage-01/protocol.json`, `protocol-tests.log`, `preparation.log` |
| M02 | PASS: universal strict Swift 6/macOS 14 native build | `build.log`, `ordinary-app-inspection.json` |
| M03 | BLOCKED: final clean first launch and runtime network observation need unlocked desktop | `native-ui.log`, `static-runtime-audit.json` |
| M04 | PASS: ordinary built app sandbox/hardened runtime and bounded entitlements inspected | `ordinary-app-inspection.json`, `built-entitlements.plist`, `built-signature.log` |
| M05 | BLOCKED: local packages/pins/scripts verified; hosted CI not run | `dependencies.log`, package build logs; CI definitions in `.github/workflows` |
| M06 | BLOCKED: 130 Foundation and 4 native unit tests pass; keyboard/VoiceOver/final screenshots pending | `package-and-native-tests.log`, `foundation.log`, `native-ui.log` |

The reproducible script passed 130 Foundation tests and 4 native unit tests, including actual source loading into TextKit with
BOM, CRLF, combining Unicode and subsequent edit preservation. Earlier manual desktop
inspection observed a first-run consent sheet and editable scratch window without
an account; it does not replace final-candidate keyboard, appearance or VoiceOver proof.
The latest UI runner reached macOS authentication and failed because the Mac is locked.
No screenshots or spoken VoiceOver observations are invented.

Xcode adds broad test-manager exceptions to a product during UI tests. `test.sh` now
uses `.build/NativeTestDerivedData`; the ordinary build uses `DerivedData`. The separate
ad-hoc XCTest runner cannot load its test bundle with hardened library validation, so
only that non-shipping runner disables hardened runtime. The app retains it. Hostless
native unit tests compile actual application sources without injecting a bundle into
the protected app. Distribution signing is **not measured**: the host has zero valid
Developer ID identities. No signing policy or sandbox exception was added to the app.

## Commands and environment

Observed macOS 26.6.2, Xcode 26.6, Swift 6.3.3, SDK 26.5 on Apple M1 Pro/16 GB.
See `mac/BuildEnvironment.md` and `logs/stage-01/environment.json`. The installed
supported toolchain replaces the recovered Xcode 27 assumption. No macOS 14 or Intel
runtime result is claimed; both target architectures compile.

Executed commands (logs outside frozen directories):

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
PATH="/opt/homebrew/opt/openssl@3/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 .venv-hwp/bin/python protocol/v0/run_checks.py
mac/scripts/check.sh
mac/scripts/build.sh
mac/scripts/test.sh -only-testing:NostrWriterTests
python3 mac/scripts/check_dependencies.py
python3 mac/scripts/inspect_app.py mac/DerivedData/Build/Products/Debug/NostrWriter.app
swift build --package-path mac/Packages/WriterHWP --scratch-path mac/.build/WriterHWP
# The same package build command was run for WriterStorage, WriterExport and WriterNostr.
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/DerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:NostrWriterTests test
# UI-only run used -only-testing:NostrWriterUITests; blocked by macOS authentication.
```

The repository-local Python/Node/OpenSSL tools are frozen protocol oracles, not app
runtime dependencies. Static runtime source inspection found no URLSession, network
connection, process launch or telemetry calls. This is explicitly not a runtime packet
capture. Dependency plugin validation admits only the reviewed pinned P256K source-copy
plugin before allowing Xcode package plugin execution.

## Remaining work

The source candidate is frozen and all obtainable Stage 01 code checks pass. Unlock the Mac for native UI testing, final light/dark
1120×760 and 760×520 observations, keyboard/VoiceOver focus, and runtime network audit.
Source and evidence are preserved locally. Hosted CI requires authorization to publish
the reviewed candidate to the exact GitHub branch. No push or external publication has
occurred. Stage 02 remains unaccepted/unstarted until predecessor evidence permits it.

Focus review corrections cover separate Normal/Locked modes, durable intent acknowledgement before
activation or extension, full presentation restoration on interruption, safe emergency cancellation,
invalid clock continuity, checked word counts, injected session IDs, and no relock after completion.
A native focus presentation adapter and word lineage remain Stage 07 work; pure reducer tests do
not establish actual system restrictions, sound behaviour, or human composition.
