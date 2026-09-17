# Current implementation handoff

Recovery date: 17 September 2026. Ready for **Stage 01 implementation**, not a claim that a Mac app or empirical certification system exists.

The complete frozen joined protocol and earlier packages are in Git. Product/UX/storage/HWP/export/Nostr/focus/security contracts, eight plans/starts, interfaces and all 60 mandatory criteria are recovered. Every supplied file and all six supplied reply sections are preserved with provenance.

## Next task

Use [START 01](product/mac/starts/START-01.md) to execute [PLAN 01](product/mac/plans/PLAN-01-FOUNDATION.md). Verify repository inputs, create the native document-app foundation and implement missing WriterFoundation helpers from recovered contracts. This is new implementation; neither the original source nor its 47-test suite survived. Do not chase ChatGPT links or recreate the missing transport: all frozen HWP files are directly committed.

Recovery host: macOS 26.6.2 (25G83), Xcode 26.6 (17F113), Swift 6.3.3, arm64. These are environment facts, not build evidence. The historical handoff selects Xcode 27/Swift 6.4; Stage 01 must resolve and record a supported toolchain. Recovery did not upgrade Xcode.

## Acceptance

Keep [M01–M60](product/mac/contracts/acceptance.json) unchanged. [Current status](product/mac/evidence/STATUS.json) marks all application criteria NOT MEASURED pending actual stage evidence. Recovery conformance tests do not validate AppKit, providers, Word/Pages, focus restrictions or notarization.

Sequence: Foundation → Documents → Editor → HWP → Export → Nostr → Focus → Release. App implementation may proceed while empirical HWP work remains unapproved; an agent cannot manufacture approval to finish it.

Read [RECOVERY-NOTES](product/mac/RECOVERY-NOTES.md) for input corrections, missing Foundation code, historical evidence labels and replacement bibliography. Stage 05 creates the missing export fixture. New preparation checks verify recovery; they are not the lost ten-test suite. [Full gap register](docs/recovery/MISSING-ARTIFACTS.md).
