# Agent entry point

Read IMPLEMENTATION.md, RECONCILIATION.md, product/mac/RECOVERY-NOTES.md and the assigned plan. Inspect HEAD and unrelated working changes. Follow the user's scope; recovery alone is not authorization to implement the app.

## Authorities

- product/mac/ contains the product contract. Execute PLAN 01 then 02–08 with predecessor evidence.
- protocol/v0/ is the immutable joined HWP authority: preserve all 69 files byte-for-byte, including historical results and publication notes. Never rebuild manifests to hide mismatches. New semantics require a new version.
- A1, algorithm/v0_2, algorithm/v0_3 and proof/hwp-c-1 are historical references; do not mix their import paths or substitute their callbacks for joined v0.
- history/ preserves evidence, not current instructions. Never silently rewrite originals.
- WriterFoundation source/tests are missing. Stage 01 creates them from contracts; the historical 47-test claim cannot be applied to new code. Keep all 60 acceptance requirements.

## Execution and evidence

Use one owner per mutable branch, Git index, build and device. Delegate bounded independent work only when useful; workers must not delegate further without authorization. Implement the assigned scope, run relevant checks and observe resulting builds for UI claims. Preserve user documents, Keychain entries, identities and unrelated changes; use isolated synthetic fixtures.

Each stage writes product/mac/evidence/STAGE-0N.md and .json with source commit, commands, results, acceptance IDs and blockers. Label PASS, FAIL, NOT MEASURED or BLOCKED with a reason. Historical evidence is not a current pass. Do not weaken requirements or invent execution, credentials, observations or empirical approvals.

Run `python3 tools/check_preparation.py` and `python3 tools/bootstrap_protocol.py`. Package-specific tests are in docs/VERIFICATION.md. Keep new logs outside frozen directories; check scripts for output-writing side effects before running.

## Product boundaries

The production approval set remains empty. NOT PROVABLE is not an accusation. Software-only observation, author keys, Nostr signatures and focus sessions cannot grant HWP authority. Implement actual conditional producer/verifier paths; an always-negative stub is not completion.

Preserve exact source bytes, asynchronous revision identity, independent trust selection, local private evidence, consent and safe recovery. Never commit real keys, private drafts, participant traces or signing credentials. External publication requires authorization for its actual destination and scope.
