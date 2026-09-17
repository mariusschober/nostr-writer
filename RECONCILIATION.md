# Astra Pro reconciliation — 17 September 2026

Scope: all 47 supplied files, including a six-section assistant-response compilation, six top-level ZIPs, the nested final protocol ZIP and expanded Chat 5/6 attachments. This is not a complete export of every original user message/tool trace; absent content is not invented.

Inspected GitHub baseline: `262cb213cda8e533a958fe21915a2406138b6f9c`, main, 70 tracked files. One branch, no tags; issue/PR searches returned none. Prior commits remain intact.

## Published versus missing

| Task / attempt | Remote baseline | Disposition |
|---|---|---|
| 1, a29313c | Research and three supplied experiment files present; exact match | Retained |
| Earlier A1 through 9874007 | Executable source/tests present | Retained unchanged |
| 2, HWP-A 0.2 | Package absent; root index refers to another version | All 43 files recovered to algorithm/v0_2; exact content, relocated paths |
| 3, 73679e0 | 18 of 37 versioned files plus root index present, all matching ZIP | Added 19 missing files |
| 4, c53e794 | All 22 HWP-C1 files present and byte-identical | Retained unchanged |
| 5, joined v0 | All 69 frozen files absent from main | Recovered directly, including 16,161,774-byte vector |
| 6, Mac preparation | Product/Swift tree absent from main | Mapped all 35 supplied attachments; identified missing claimed code |
| Seven later attempts, f266e9a…262cb21 | Optimistic README, corrupt transport, absent claimed tree | Replaced current claims; preserved failed evidence |

[RECOVERY-INVENTORY.json](history/astra-pro/RECOVERY-INVENTORY.json) records original and ZIP-member hashes, baseline Git blobs and attachment destinations. [SOURCE-OF-TRUTH-MANIFEST.json](SOURCE-OF-TRUTH-MANIFEST.json) pins the reconciled snapshot. Historical/frozen bytes remain distinct from new recovery tools and docs.

## Failed later publication

Latest committed transport: 15,000 bytes, SHA-256 `aab1ac798924a8a7b06d92e9d5b3921a1bbc81e99d2fdf8ea723f66b4dd7f2f3`. Workflow expectation: 298,576 bytes and `7b2d159bed88b75ded0aa8ff14fcd3e789ef10f92e1e9ee1763db0a276e86a0`. XZ failed with `Corrupt input data`. The f266e9a transport was also corrupt (15,009 bytes). Partial decoding exposed initial documents and incomplete inventory, not missing Swift source. Created blobs and README claims were not publication of the source tree.

Both corrupt transports, prior documents, workflow, checksums and probes are preserved in [history/failed-publication](history/failed-publication/README.md). Active broken transport/workflow paths are removed. Replacement CI verifies committed material with read-only permissions; it cannot materialize code or push to main.

The frozen distribution has its own source-only commit `df574612a0101150e2259dc80019058d0b4b5d6b` and annotated locator tag `human-writing-protocol-v0`. The tag is a locator for the independently hashed distribution, not a production approval.

## Final version and stale claims

- Final definition: `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`.
- FREEZE.json SHA-256: `c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88`.
- Final distribution: 67 inventoried files plus FREEZE.json/FREEZE.sha256; 178 historical tests.
- Task 5's earlier stdout (174 tests, `559e025c…`) is intermediate, not the final delivered freeze. Original text is preserved.
- Frozen publication notes retain “not performed”: historical bytes are not rewritten to describe later recovery.
- Prior claims of a reconstructed 47-test Swift package are unsupported by accessible source. They are historical claims, not current validation.

## Bounded preparation repairs

Exact originals remain in history/astra-pro/originals. Current product docs link a recovery notice. INPUTS.md and the new bootstrap verify directly committed files instead of requiring missing transport chunks. SOURCES.md is a labeled replacement bibliography. Original Foundation README remains, with a current missing-source warning. Stage 01 owns that implementation; Stage 05 creates the missing export fixture. [Gap register](docs/recovery/MISSING-ARTIFACTS.md).

The prior repair note claims a NIP-44 arithmetic fix, but the supplied NOSTR attachment has no numeric example to replace. Current contract adds the verified boundary: 65,537 plaintext bytes pad to 81,920 and yield 109,324 Base64 characters (6-byte prefix + 65-byte envelope). The original stays unchanged in history. PLAN 03’s 12–28 pt font range was aligned with the detailed UX contract’s 13–32 pt; original variants remain archived.

[Current observed checks](docs/recovery/VERIFICATION.md) are separate from historical RESULTS/PREPARATION. Recovery is not a full independent security audit, empirical detector validation, native capture approval or Mac acceptance. No real proof or production approval is created.
