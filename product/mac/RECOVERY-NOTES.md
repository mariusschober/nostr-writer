# Recovery notice

Recovery occurred on 17 September 2026; current-state clarifications were added on 30 September. Read before any PLAN. Exact originals remain in history/astra-pro/originals/Chat 6. Product requirements and all 60 acceptance rows are retained. [IMPLEMENTATION.md](../../IMPLEMENTATION.md) is the continuation entry point.

1. **Protocol directly committed.** `python3 tools/bootstrap_protocol.py` verifies all 69 files, including the vector. Missing transport chunks are no longer required; do not regenerate manifests.
2. **Original WriterFoundation source was missing.** Stage 01 implemented a new package from those contracts; its source/tests now exist. Do not apply the historical 47-pass claim to the new code. Later stages consume Stage 01's accepted implementation.
3. **PREPARATION.md/json are historical reports.** They establish neither current source availability nor native acceptance. Recovery execution is recorded in docs/recovery/VERIFICATION.md; application acceptance is in the stage ledgers. Stages 01–02 are recorded as accepted. Stage 03 remains blocked and unaccepted.
4. **Bibliography reconstructed.** SOURCES.md provides primary entry points, not the missing original list. NostrShot source findings remain historical until reproduced; recovery verified its pinned Package.swift, not every runtime claim.
5. **Export fixture absent.** Stage 05 creates fixtures/export-torture.md from EXPORT.md before using it; required coverage is unchanged.
6. **Toolchain observations are dated.** Recovery observed Xcode 26.6/Swift 6.3.3 without an app build or upgrade. Later stage evidence records Xcode 27/Swift 6.4. Inspect the actual installed toolchain before new work; neither dated observation establishes today's environment.

Final definition: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`, 178 final conformance tests, zero production approvals. Reconciliation resolves intermediate historical values. Nothing here changes frozen semantics.

A small editorial conflict was resolved in favor of the detailed UX contract: editor size range is 13–32 pt; PLAN 03 previously said 12–28. The original versions remain in history.
