# Copyable PLAN-mode prompt — DeepSeek V4.1 Flash

Use this only when you want one planning pass before implementation. For direct execution, use the [start prompt](STAGE-03-DEEPSEEK-START-PROMPT.md). This prompt intentionally narrows the recovered plan's “implement now” execution clause to a read-only planning task; all product and evidence requirements still apply.

---

You are DeepSeek V4.1 Flash, preparing the implementation of **Stage 03 only** for Nostr Writer's native macOS app. Astra owns architecture, difficult decisions and final review. Do not spawn subagents. Work in PLAN mode: inspect and formulate an executable plan; do not implement, build, run tests, change signing/accounts, start device interactions, push or start another stage in this planning pass.

Repository: https://github.com/mariusschober/nostr-writer

Local workspace: `/Users/schober/Projects/Nostr Writer`.

Start from `implementation/stage-02`, whose accepted predecessor is `b8568c09530b90e28a3d1fb817335c6a980fc116` and accepted application source is `67302883935fcfaba2b9668a04df3aee60820fcd`. `main` was only the recovered preparation baseline at handover. Inspect current HEAD, working changes and branch ancestry before drawing conclusions; do not reset or overwrite unrelated work.

Read these current branch files first:

- `product/mac/handoffs/STAGE-03-DEEPSEEK-HANDOVER.md`
- `product/mac/handoffs/STAGE-03-DEEPSEEK-PLAN.md`
- `AGENTS.md`, `IMPLEMENTATION.md`, `RECONCILIATION.md`, `product/mac/RECOVERY-NOTES.md`
- `product/mac/plans/PLAN-03-EDITOR.md`, `product/mac/evidence/STAGE-02.md` and `.json`

Online entry: https://github.com/mariusschober/nostr-writer/blob/implementation/stage-02/product/mac/handoffs/STAGE-03-DEEPSEEK-HANDOVER.md

Follow the handover's prioritized contract and source map. Read full UX, PRODUCT, ARCHITECTURE, DATA, SECURITY, HWP, interfaces, FOCUS mutation restrictions and EXPORT Markdown grammar. Inspect the frozen telemetry/replay authority before proposing capture semantics. WriterFoundation now exists; historical missing-source/test claims are not current evidence. Stage 02 is accepted, including explicitly owner-confirmed VoiceOver; do not reopen unchanged predecessor setup.

Produce one concrete implementation plan for M14–M21, refining the existing six-work-package plan rather than re-planning the product. Keep the planning pass bounded to approximately 20–30 minutes after the required reading; if repository drift prevents a decision, name it precisely. Include:

1. Verified input commit/branch and any unrelated changes or actual prerequisite blocker.
2. A short effort range and ordered integrated milestones with exact existing files to edit and proposed files to add. The first milestone must connect the mutation gateway to the real editor/session/recovery path.
3. Clear ownership of native text storage, immutable source revisions, native undo/IME, actual observation causes, root ancestry, encrypted detailed history versus rolling recovery, consent/resource boundaries, annotation scope, stale parser results and range-anchored on-device dictation.
4. A table mapping every M14–M21 requirement to implementation and its smallest sufficient automated/native evidence. Retain the required 1,000-operation Unicode replay, real input matrix, actual 100k-word timings and prescribed UI evidence; do not expand testing beyond the contracts.
5. Risks requiring an architecture decision, with your recommended resolution and evidence; distinguish platform limitations from test/tool failures. Ask the owner only for information/access that materially blocks necessary work.
6. Commit/handoff sequence, one candidate for final native verification, and the exact next implementation action. No mandatory FAIL/BLOCKED/NOT MEASURED may be presented as completion.

Preserve all 69 frozen `protocol/v0` files, historical originals, all 60 acceptance requirements, existing encrypted recovery, source bytes, keys and user documents. The production HWP approval set stays empty. Do not fabricate native deliveries, key-up/timing, physical-input certainty, source parents or positive HWP authority. No silent network speech fallback, private-history publication, relay work, locked-session enforcement or full export renderer belongs in this stage.

Tests must remain minimal and purposeful: propose affected checks only, no repeated passing checks and no retry loops. `mac/scripts/test.sh` is broad even with `-only-testing`; select focused commands instead. Return the plan for Astra/owner review, then stop. Implementation begins only with the separate start instruction.
