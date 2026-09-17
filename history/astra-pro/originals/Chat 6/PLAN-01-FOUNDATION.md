# PLAN 01 — establish the native build and authoritative inputs

## Outcome and entry

Create the buildable native Mac product shell and development/test infrastructure on which all later stages depend. This is the first implementation stage; the current repository contains protocol research, the frozen-input transport and preparation kernels, not a Writer app. Acceptance ownership: **M01–M06**.

Read `product/mac/INPUTS.md`, `REPOSITORY-AUDIT.md`, `PRODUCT.md`, `ARCHITECTURE.md`, `UX.md`, `SECURITY.md`, `MVP-COMPLETE.md`, the acceptance matrix and the prepared WriterFoundation package. Do not start from `algorithm/reference.py` or the old crypto callback. The joined `protocol/v0` is authoritative. NostrShot is a source pin, not a prebuilt app to rename.

## Establish the exact baseline

Run the frozen-input bootstrap and verify the original FREEZE inventory and protocol digest. If the large deterministic vector is omitted from the checkout, regenerate only that vector with the frozen generator and compare its exact SHA-256/size to the immutable manifest. Never run the manifest builder to make differences disappear. Run the 178 frozen tests in bounded partitions if necessary, the Node interoperability checker and freeze check. Archive logs outside the frozen directory. Distinguish archived prior results from this run.

Record `sw_vers`, `xcodebuild -version`, SDK list, Swift version and hardware in `mac/BuildEnvironment.md`. The selected baseline is macOS 14 deployment with Swift 6 language mode and the current Xcode identified in SOURCES. Install/resolve the current stable developer toolchain through the user's established environment, not an unsigned download. Lack of a Mac is a real stage blocker; do not fabricate an Xcode project test result from a Linux compiler.

Resolve dependencies named in ARCHITECTURE. Preserve NostrShot's known P256K/KeyboardShortcuts pins initially; pin exact supported BigInt, swift-markdown, ZIPFoundation and CryptoSwift revisions after checking deployment compatibility. Record upstream URL, revision, license, purpose and transitive dependencies. Do not add a second secp256k1 implementation because an older NIP-44 reference uses one. Do not download or redistribute proprietary iA fonts. Record NostrShot owner-source reuse separately from third-party licenses.

## Native project and responsibility boundaries

Create a checked-in `mac/NostrWriter.xcodeproj`, shared `NostrWriter` scheme, unit/UI test targets, xcconfig files and app entry point. Use a regular document app with Dock presence, File/Edit/Format/View/Focus/Window/Help menus and Settings. Bundle identifier is `com.mariusschober.nostrwriter`; development/test targets have separate suffixes and Keychain services. Set deployment 14.0, strict Swift 6 checking, arm64+x86_64 distribution architectures and appropriate availability guards. Intel testing uses supported macOS 14–26, not an assertion that macOS 27 runs on Intel.

Wire AppKit lifecycle/NSDocumentController/NSWindowController with SwiftUI chrome. Create local package targets WriterFoundation, WriterStorage, WriterHWP, WriterExport and WriterNostr, without placeholder public APIs that pretend to work. The preparation WriterFoundation helpers remain small and testable; add typed errors, identifiers and dependency injection rather than an application-wide service locator. Async services operate on immutable snapshots. A mocked service may be used in test previews but must be impossible to mistake for a production capability.

Build the initial 1120×760 window, minimum 760×520, native toolbar/menu placeholders, sidebar visibility and central editable scratch view. This scratch view is explicitly stage-local; Stage02 replaces persistence and Stage03 completes the editor. No new account, cloud login, onboarding survey, proof score or Nostr screen before the user can write. Implement first-run recording consent from UX U01 and keep the choice distinct from permission to publish or upload evidence.

Set App Sandbox and Hardened Runtime on from the first commit. Add only described entitlement needs: selected-file read/write, outbound networking, optional audio input; privacy usage descriptions where required. No Accessibility, Input Monitoring, Screen Recording, Full Disk Access, broad temporary exceptions, global event tap or privileged helper. The prepared presentation APIs must stay optional and bounded. Use separate development/test storage roots; automated tests must not touch the user's real document library or Nostr keys.

## Automation and foundational interfaces

Implement scripts `mac/scripts/test.sh`, `build.sh` and `check.sh` with strict failures and explicit toolchain paths. `test.sh` runs native unit/UI tests and package tests; `check.sh` runs preparation validation and frozen integrity checks. Build a standalone `hwp-verify` native CLI target interface now, but report unsupported functionality until Stage04 completes it. A binary that always rejects is not future conformance completion.

Create GitHub CI that uses an actually available macOS runner with a compatible Xcode, pinned third-party actions and read-only permissions by default. Run portable preparation/protocol checks separately on Linux. Cache dependency artifacts by lockfile digest; do not cache unvalidated trust policy state. Make release signing a separate protected/manual workflow with no secrets in pull-request jobs. Do not enable live Nostr publication in default CI.

Add shared protocols and value types described in ARCHITECTURE and contracts/interfaces.md. Define main-actor DocumentSession ownership, mutation entry point, SourceSnapshot, DurableRevision, export request/result, capture boundaries, proof result and outbox identifiers. Methods that are not implemented throw a typed unsupported error; no canned success. Capture timestamps/UUID/randomness/key stores/network/file coordination are injectable for tests.

## Verification and exit

Run the prepared 47 tests unchanged, build the app with code signing disabled for unit CI, launch it on Mac and exercise menus, window resizing, first-responder focus and recording consent. Take actual light/dark/narrow-window screenshots and check native traffic lights, toolbar alignment, VoiceOver focus order and keyboard access. Confirm first launch produces no network requests and no telemetry until consent. Verify entitlements from the built bundle, not just the source plist.

Run an arm64 and x86_64 compile, document the actual runtime coverage separately, and ensure no process invokes Python at app launch. Check the frozen SHA again after all build scripts. At exit the app builds and opens cleanly, dependencies are locked, tests are reproducible, shell UX is coherent, and all M01–M06 have evidence. Do not implement storage/network/proof shortcuts to make later requirements appear present.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-01.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-01.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
