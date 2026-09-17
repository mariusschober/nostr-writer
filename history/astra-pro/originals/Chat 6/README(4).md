# Nostr Writer for Mac — implementation handoff

Prepared 2026-09-16. This directory is the product contract and coding-agent execution sequence, not a completed Mac application. The frozen Human Writing Protocol is an upstream constraint, not a claim of scientific validation.

**Start with PLAN 01, then execute 02–08 in order.** Each stage owns implementation and verification, not another round of planning. Give a coding agent its matching file in `starts/`; all detailed instructions are in `plans/`. Do not run adjacent stages against the same mutable branch in parallel. Independent tests or assets may be delegated within a stage under its owner.

| Stage | Complete implementation outcome | Detailed prompt | Short launch prompt |
|---|---|---|---|
| 01 | Frozen inputs, native project, contracts, build/test foundation | [PLAN 01](plans/PLAN-01-FOUNDATION.md) | [START 01](starts/START-01.md) |
| 02 | Durable local documents, library, recovery and File Provider storage | [PLAN 02](plans/PLAN-02-DOCUMENTS.md) | [START 02](starts/START-02.md) |
| 03 | Finished writing interaction, provenance-aware mutation capture and assistance | [PLAN 03](plans/PLAN-03-EDITOR.md) | [START 03](starts/START-03.md) |
| 04 | Native HWP producer/verifiers, exact binding, guarded proof experience | [PLAN 04](plans/PLAN-04-HWP.md) | [START 04](starts/START-04.md) |
| 05 | Shared preview, polished PDF/DOCX, portable documents/evidence | [PLAN 05](plans/PLAN-05-EXPORT.md) | [START 05](starts/START-05.md) |
| 06 | Hardened Nostr identity, durable publishing, long form and encrypted drafts | [PLAN 06](plans/PLAN-06-NOSTR.md) | [START 06](starts/START-06.md) |
| 07 | Optional disciplined sessions, multi-display protection and background sound | [PLAN 07](plans/PLAN-07-FOCUS.md) | [START 07](starts/START-07.md) |
| 08 | Integrated, accessible, tested, signed and distributable Mac MVP | [PLAN 08](plans/PLAN-08-RELEASE.md) | [START 08](starts/START-08.md) |

Read [PRODUCT.md](PRODUCT.md), [UX.md](UX.md), [ARCHITECTURE.md](ARCHITECTURE.md) and [MVP-COMPLETE.md](MVP-COMPLETE.md) before coding. [DATA.md](DATA.md), [HWP.md](HWP.md), [NOSTR.md](NOSTR.md), [EXPORT.md](EXPORT.md), [FOCUS.md](FOCUS.md) and [SECURITY.md](SECURITY.md) are binding cross-stage contracts. [REPOSITORY-AUDIT.md](REPOSITORY-AUDIT.md) separates inspected facts from required implementation. [SOURCES.md](SOURCES.md) records the primary references. The machine-readable [acceptance matrix](contracts/acceptance.json) assigns every required outcome to a stage.

## What complete means

There is one definition: every mandatory row in `contracts/acceptance.json` passes against the same release commit, every stage report identifies actual executed evidence, and all gates in `MVP-COMPLETE.md` pass. A mock, disabled required feature, untested signing recipe or README promise is not completion. Conversely, a real-world HUMAN-WRITTEN badge is **not** a completion shortcut: the current production approval set is empty, so the correct production behaviour is NOT PROVABLE and no HWP issuance. The full conditional pipeline must nevertheless work and be tested; the app must verify actual externally admissible proofs when such evidence exists.

## Input precedence

User product requirements govern the product; frozen HWP governs HWP meaning. This handoff resolves their interaction without weakening either. A PLAN cannot silently supersede HWP. If an implementation reveals a genuine normative contradiction, keep writing/data safe, reject the affected proof, record a narrowly scoped protocol defect and do not regenerate a freeze to hide it. Routine technical work is resolved by the stage owner; do not convert a stage into a request for product redesign.

The approved source pins, frozen digest and hydration procedure are in `INPUTS.md`. Never mistake the legacy `algorithm/` or `proof/hwp-c-1/` directory for the joined v0 authority. `mac/Packages/WriterFoundation` contains small executable app-contract kernels only; it is not an HWP implementation, capture attestation or Mac UI.

## Agent finish protocol

At each stage: inspect current HEAD and the predecessor report; preserve unrelated changes; implement the assigned scope; run relevant prior tests and new tests; capture actual Mac screenshots where UI changes; commit the stage coherently; write `product/mac/evidence/STAGE-0N.md` with commit, commands, results, visual evidence, limitations and next-stage state. A failed required gate means that stage remains incomplete. Do not rewrite test expectations just to obtain green results. Never place real keys, private drafts, research participant traces or Developer ID credentials in Git.
