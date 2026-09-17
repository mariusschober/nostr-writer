# Stage 01 — native foundation (acceptance blocked)

Stage 01 is **not accepted**. This is a live implementation report, not a substitute
for the frozen acceptance matrix. Machine-readable status is in `STAGE-01.json`.
Input: `3fdab5b1f8d75720c3025e8604f947e2307c31e2`. Source candidate: `ddac4a30073f9eaf7aa9586ed86c449a488bcea4` on
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
| M02 | PASS: final universal strict Swift 6/macOS 14 native build | `logs/stage-01-unlocked/build.log`, `ordinary-app-inspection.json` |
| M03 | PASS: final clean consent/account-free writing; no app TCP/UDP rows during sampled runtime observation | `logs/stage-01-unlocked/tests.log`, `network.csv`, `network-control.csv`, `results.json` |
| M04 | PASS: final ordinary build sandbox/hardened runtime and bounded entitlements inspected | `logs/stage-01-unlocked/ordinary-app-inspection.json` |
| M05 | BLOCKED: hosted regular-window geometry failed twice; session-scoped display correction pending | `logs/stage-01-ci/first-run.json`, `second-run.json`, `second-run-diagnostic.log` |
| M06 | PASS: 130 Foundation, 4 native unit and 3 native UI tests pass; owner confirms listened-to VoiceOver is fine | `foundation.log`, `logs/stage-01-unlocked/tests.log`, `screenshot-index.json`, `voiceover-owner-observation.json` |

The unchanged Foundation implementation previously passed 130 tests. The final source
candidate now passes all four native unit and three native UI tests in one run. Actual
1120×760 and 760×520 screenshots in both appearances were reviewed. The real resize
edges are exercised; there is no startup geometry override. An observed initial-focus
defect was fixed by setting the editor as the window's initial first responder.

The clean consent test uses a fresh isolated defaults suite, requires all three explicit
choices, and verifies Escape selects recording off and reaches writing without an account.
Network accounting starts before launch and reports no NostrWriter TCP/UDP rows through
the final suite. A synthetic loopback control confirms the observer sees traffic when
present. This is bounded sampled process accounting, not packet capture or a universal
absence proof; details and limits are in `logs/stage-01-unlocked/results.json`.

VoiceOver was enabled and its first-use dialog/tutorial and process were observed.
Its inspection call stalled for 715.835 seconds despite a requested 20-second timeout.
The agent did not observe spoken labels and navigation order. VoiceOver was restored
to its original off state and that setting was checked. Subsequently, in response to
the requested editor/sidebar/toolbar/status/menu check in the final ordinary app,
the owner reported: “Voiceover is fine, I listened to it.” This direct owner
observation resolves the earlier M06 blocker; no agent audio capture is claimed.
The earlier locked-desktop and failed UI attempts remain historical diagnostics, not
current passes. No further testing loop is authorized by the user's latest direction.

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

The final local source is frozen at `ddac4a30073f9eaf7aa9586ed86c449a488bcea4`.
Stage 01 remains unaccepted pending the hosted CI result (M05). VoiceOver observation
(M06) is now owner-confirmed. The Mac is no longer recorded as locked. Native keyboard, consent,
appearance, resizing, ordinary signing/entitlements and bounded network observation
are now measured. `logs/stage-01-unlocked/voiceover-owner-observation.json` records
the owner's confirmation and the exact build named in the requested check.

The owner authorized the push to `mariusschober/nostr-writer`, branch
`implementation/stage-01`; reviewed commit `e49557e` was pushed successfully.
[Hosted CI run 35281226918](https://github.com/mariusschober/nostr-writer/actions/runs/35281226918)
and [35282183578](https://github.com/mariusschober/nostr-writer/actions/runs/35282183578)
failed the same four regular-window dimension assertions (1024×674 versus 1120×760).
Builds, 130 Foundation tests, four native unit tests, consent, writing/undo and narrow sizing passed.
The second setup saw 1280×960, but the SDK documents that `CGDisplaySetDisplayMode`
reverts when its process exits. The correction now uses `CGCompleteDisplayConfiguration`
with `.forSession`, restricted to disposable hosted runners. It changes no application
behavior or test assertion. No local UI or Foundation rerun is needed for this CI-only change.
Stage 02 cannot be accepted or started from an accepted predecessor yet. The separate `preparation/native-cores` worktree contains independent,
unmerged components with their own evidence and no later-stage acceptance claim.

The root handoff, `mac/README.md` and initial `STATUS.json` are recovery-snapshot files
pinned by the source manifest. Their original 'no app' statements are historical;
this current stage report and `mac/docs/DEVELOPMENT.md` record actual implementation
without rewriting the pinned recovery originals.

Focus review corrections cover separate Normal/Locked modes, durable intent acknowledgement before
activation or extension, full presentation restoration on interruption, safe emergency cancellation,
invalid clock continuity, checked word counts, injected session IDs, and no relock after completion.
A native focus presentation adapter and word lineage remain Stage 07 work; pure reducer tests do
not establish actual system restrictions, sound behaviour, or human composition.

## Unlocked checkpoint commands

Final candidate native run, with a process-scoped `nettop -n -p NostrWriter -P -L 0 -s 1`
observer started before launch and stopped after completion:

```sh
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/.build/NativeTestDerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -resultBundlePath /private/tmp/nostr-writer-stage01-candidate-20260917.xcresult test
mac/scripts/build.sh
python3 mac/scripts/inspect_app.py mac/DerivedData/Build/Products/Debug/NostrWriter.app
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

Final ordinary binary SHA-256:
`935a0cfe0ca88383ef89c2f9de8878d26ac51bfe1db065fb2254b9770ab13c2f`.
Full current evidence is in `logs/stage-01-unlocked/`; earlier logs are retained in
`logs/stage-01/`. No protocol manifest, acceptance definition or historical original
was changed. Future checks must remain minimal and scoped to actual changes.
