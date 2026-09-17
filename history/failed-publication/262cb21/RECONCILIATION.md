# Astra research/product reconciliation — 2026-09-16

This repository is the source of truth for the Human Writing Provenance work generated in the preceding ChatGPT/Astra sessions.

## What had already reached GitHub

Before this reconciliation, `main` ended at `c53e794a11aa801b553af462fe5da33593e12eee`. The research foundation, the HWP-A 0.3 adversarial **documents/results** and HWP-C/1 cryptographic core had been committed. HWP-C/1 was complete and browsable. HWP-A 0.3's GitHub directory lacked the executable `hwp_a/`, tests, several artifacts and check scripts because those source uploads had previously failed. The joined frozen Human Writing Protocol v0 and the Mac MVP implementation handoff had not been committed. Some binary Git blobs from a failed later attempt were orphaned and were not reachable from `main`.

## What this reconciliation restores

- Complete HWP-A 0.3.0 generated package, including executable reference source/tests/artifacts.
- Complete HWP-C/1 generated package (also retained in its existing browsable directory).
- Complete frozen Human Writing Protocol v0, protocol-definition SHA-256 `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`.
- Complete Mac MVP product/architecture/UX/storage/HWP/Nostr/export/focus/security contracts, 8 detailed PLAN prompts, 8 START prompts, and the 60-criterion completion contract.
- WriterFoundation preparation kernels and tests.
- A deterministic compressed archive at `artifacts/source-of-truth/astra-history-2026-09-16.tar.xz` with an embedded per-file SHA-256/provenance manifest, so the complete historical package remains recoverable even if a working-tree file is later edited.

## Byte preservation versus reconstruction

The HWP-A 0.3, HWP-C/1 and HWP v0 package files are byte-preserved from the generated ZIP artifacts available in the conversation runtime. The Mac handoff documents/plans were recovered from exact conversation attachments. The direct current `product/mac/NOSTR.md` corrects one implementation-planning arithmetic error from the earlier handoff: under the pinned current NIP-44 padding formula, a 65,537-byte plaintext produces 109,324 Base64 characters, not 92,836. The raw earlier attachment remains preserved inside the source-of-truth archive/history material.

The original WriterFoundation **source files** were not retained as conversation attachments; only its README and recorded `47/47` result survived. Its current source/tests are therefore explicitly reconstructed from the preserved contracts rather than falsely represented as byte-identical historical source. The reconstructed package again passes 47/47 tests on Linux Swift 6.2.1. This provenance distinction is intentional.

## Scientific status

Reconciliation changes repository availability, not scientific validity. No real participant detector model, independently admitted native capture profile, or production Human Writing Proof release exists. `NOT PROVABLE` never means AI-written. Test policies/fixtures cannot authorize production issuance. Application implementation must preserve the frozen protocol's exact claim and trust semantics.

## Verification

After materialization, run:

```sh
python3 tools/check_preparation.py
python3 protocol/v0/tools/check_freeze.py
python3 -m unittest discover -s algorithm/v0_3/tests -v
swift test --package-path mac/Packages/WriterFoundation
```

Protocol v0's own README/RESULTS contain its full conformance commands and historical test evidence. Native macOS application/UI/cloud/export/notarization acceptance remains work for the eight implementation stages.
