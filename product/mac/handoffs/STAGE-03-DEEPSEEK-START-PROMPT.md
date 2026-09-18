# Copyable implementation start prompt — DeepSeek V4.1 Flash

Sending the prompt below starts **Stage 03 only**. It does not authorize Stage 04 or resume all eight stages automatically. The separate [PLAN-mode prompt](STAGE-03-DEEPSEEK-PLAN-PROMPT.md) is optional.

---

Implement **Stage 03 of Nostr Writer's macOS application end to end**, starting from accepted Stage 02. You are DeepSeek V4.1 Flash, the single implementation worker; Astra owns architecture, difficult decisions and final review. Do not spawn subagents. Own one implementation branch, Git index, build and Mac device session; coordinate ownership before touching a shared checkout/device.

Work in `/Users/schober/Projects/Nostr Writer`, repository https://github.com/mariusschober/nostr-writer. Read the current `implementation/stage-02` handover:

https://github.com/mariusschober/nostr-writer/blob/implementation/stage-02/product/mac/handoffs/STAGE-03-DEEPSEEK-HANDOVER.md

And the detailed execution plan:

https://github.com/mariusschober/nostr-writer/blob/implementation/stage-02/product/mac/handoffs/STAGE-03-DEEPSEEK-PLAN.md

Inspect HEAD, status, unrelated changes and remote branches first. Stage 02 acceptance is commit `b8568c09530b90e28a3d1fb817335c6a980fc116`, with application source `67302883935fcfaba2b9668a04df3aee60820fcd`. `main` was the preparation baseline, not the completed app. Verify the accepted checkpoint is an ancestor, read the current Stage 02 ledger, and create `implementation/stage-03` from the Stage 02 handover tip. If the Stage 03 branch already exists, inspect and continue the correct work without overwriting it. Preserve unrelated changes and user data.

Read `AGENTS.md`, `IMPLEMENTATION.md`, `RECONCILIATION.md`, `product/mac/RECOVERY-NOTES.md`, the original `product/mac/plans/PLAN-03-EDITOR.md`, all named contracts and the source map in the handover. The new plan supplements those requirements; it does not replace them. Historical missing-WriterFoundation and historical test-count claims are stale preparation facts. Stages 01 and 02 are accepted, including owner-confirmed VoiceOver. Do not repeat unchanged predecessor signing/cloud/accessibility setup.

Give a brief effort estimate and the bounded M14–M21 checklist, then implement. Do not stop after another roadmap or ask routine reconfirmation. Follow the integrated sequence: exact mutation gateway and consented encrypted local journal; finished native editor/Markdown navigation; ancestry-bound annotations and inspector; native assistance/on-device dictation; one final acceptance candidate and truthful evidence. Use the existing document/session/recovery code and pinned dependencies.

Mandatory boundaries:

- Live TextKit 2 text storage owns editing; immutable revision snapshots own downstream work. No stale SwiftUI String write-back or legacy TextKit downgrade. Preserve exact UTF-8 source, native input/undo, caret/selection and Stage 02 recovery/save semantics.
- Observe actual native causes; unknown/opaque input is a gap or unsupported origin, never invented physical typing. Keep app-descriptive history separate from frozen HWP evidence. Internal copy/move/undo and annotation scope need real ancestry, not matching text guesses.
- Detailed/deleted-text history requires explicit consent and encrypted persistence. Recording off, resource exhaustion or history-store failure must keep normal writing/recovery usable. History is retained until deletion; warn at 1 GiB and pause detailed recording at 2 GiB as contracted.
- Optional dictation is explicit, on-device, permission-aware, generation/range-bound and cancellation-safe. Never silently fall back to network speech or overwrite newer unrelated text. Add no global input-monitoring/AX privilege.
- Preserve all 69 frozen protocol files, historical originals and all 60 acceptance definitions. Production HWP approvals remain empty; local software observations cannot approve an authority. No positive HWP claim, model training, Nostr publication, full PDF/DOCX renderer or locked-session/sound implementation in this stage.

Keep verification minimal but sufficient for the mandatory contract. Run entry freeze/preparation checks once after inspecting their side effects. Compile/run the relevant fast checks before a coherent implementation handoff. Complete the prescribed 1,000-operation Unicode replay, focused mutation/race/resource checks, real native input/assistance/VoiceOver matrix, 100k-word timings and actual light/dark/narrow editor/inspector/annotation/error observations. Reuse one signed candidate; only repeat checks affected by later changes. Never call a skipped/unrun check a pass. After two failures at the same problem, stop retrying, identify whether it is code/fixture/environment, and change approach. Do not add broad test loops or repeatedly inspect unchanged state.

Bring architecture conflicts and unresolved difficult failures to Astra with a concrete recommendation. Continue independent useful work while waiting for genuinely required user access/consent/observations. Ask precisely for what is unavailable, in plain language. Preserve existing signing identities and synthetic-fixture scope; do not request account recreation or store credentials in Git.

Record actual commands, source commits, candidate hashes, observations and every M14–M21 result in `product/mac/evidence/STAGE-03.md` and `.json`, with supporting synthetic artifacts outside frozen directories. Keep status incomplete while any mandatory result is FAIL/BLOCKED/NOT MEASURED. Do not claim visual behavior without observing the resulting build or attribute an owner observation to agent capture.

Commit coherent source/tests/resources/evidence and **push `implementation/stage-03` to `origin` in mariusschober/nostr-writer**. Push authorization covers this project branch, not merging main, releases, relay publication or private evidence. Do not commit private drafts, audio, keys, credentials or build products. Request Astra's final review of the integrated result and acceptance evidence. Report commit/branch links, completed capabilities and exact remaining blockers. **Stop after Stage 03; do not begin Stage 04.**
