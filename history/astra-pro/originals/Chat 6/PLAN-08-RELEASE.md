# PLAN 08 — integrate, harden and ship the complete Mac MVP

## Outcome and entry

Starting from accepted Stages01–07, bring the entire product—not merely isolated modules—to the single completion definition. Own **M52–M60**, and revalidate **all M01–M60** against one release commit. Read every predecessor report, MVP-COMPLETE, acceptance matrix, UX, SECURITY and INPUTS. Do not add new product scope, loosen HWP, hide failing mandatory features or call an unsigned development binary a completed distribution.

## Cross-feature journeys

Execute the exact end-to-end journeys below on a release-configured app with no developer override flags.

1. Clean install, decline recording, create a new long document offline, write/revise, save locally, close/reopen and export polished PDF/DOCX. No account is required; no network requests are made before Nostr opt-in. Repeat with recording consent and verify private history is local/encrypted, current production result NP and no HWP file/signature is emitted.
2. Select an iCloud location and a Google Drive for desktop location, edit offline, reopen, receive an external conflicting version and preserve both. Trigger app crash/diskfull during writes and recover exact durable text. Inspect local/provider/recovery indicators for truthful wording rather than “cloud synced” guesses.
3. Compose with native IME, spelling correction, optional on-device dictation and an attributed quotation. Inspect the exact origin ranges; verify edits, assistance and exclusions survive save/export without new false provenance. Turn recording off mid-document, resume later and confirm the gap is permanent, not backfilled.
4. Set up a disposable Nostr identity, publish a kind30023 article, revise it, obtain latest naddr and exact-version event references, kill the app around ACK and retry the same signed event. Publish a Quick Post without losing a newer draft. Enable private NIP37 relay drafts, verify an extended-size encrypted draft, reconnect and resolve a genuine remote/local conflict. No plaintext draft/history leaks.
5. Start time/word locked sessions with sound, attempt every supported paste/app/window/screen escape path, attach/remove a display, sleep/wake and use emergency exit. Force quit/relaunch never resurrects restrictions. Saving/recovery takes precedence. Session completion never produces HWP certification.
6. Run complete native conformance P/V/R against frozen vectors in the isolated test target and the independent Python/Node tools. Confirm TEST-ONLY does not become productionHUMAN-WRITTEN, stale/proofscope/substitutedsource/dishonestevaluator behaviour stays correct, and public proof verification remains usable without application servers. Complete private disclosure/export/import is tested without publishing real evidence.

## UX quality and accessibility completion

Inspect every UX screen U01–U15 with real screenshots and interactions in light/dark, narrow/default/large widths, keyboard-only, VoiceOver, increased contrast, Reduce Motion, large editor font, RTL and at least one IME. Fix alignment, missing names, focus traps, contrast, unhelpful empty states and ambiguous labels. Native traffic lights, menus, sheets, window sizing and keyboard conventions should feel like a Mac application, not web controls painted into a window.

No serious function may be available only from an undocumented shortcut or a Settings checkbox with no effect. All button labels reflect the actual operation: first relay acceptance, local save, optional draft sync, known assistance, not-provable proof state. No “AI written”/“100% human”/“tamper-proof”/“unbreakable focus” claims. Test interrupted and denied-permission paths at least as carefully as success paths. Avoid unnecessary persistent banners that displace the writing surface.

Preview and export inspect every page of Editorial/Manuscript torture documents in A4/Letter, with Word/Pages round-trip structural checks. Imported file and archive errors retain the original. Help explains exact source proof versus rendered artifact, ordinary assistance versus qualifying spans, private history, remote draft retention and emergency exit.

## Performance, privacy and security

Measure on the reference baseline M1/8GB or a slower supported Mac, identifying device/OS, releasebuild and fixture digest. On a100k-word source: p95 key-event-to-updated-frame ≤50ms during save/index background load; no main-thread stall over100ms attributable to HWP/export/network. Warm document opening ≤3s and warm app-to-editable-window ≤2s on the baseline local disk. Idle foreground without audio/network work averages<1% of one CPU core over60s. With HWP evaluation active, editor responsiveness remains within the same typing target and cancellation takes effect within1s; memory/resources obey protocol and app caps. Treat these as measured gates, not marketing numbers derived from a faster test machine.

Run Address/Thread Sanitizer where applicable, strict concurrency warnings, parser fuzz suites and resource-limit tests. Test malformed CBOR/signatures/private ZIP, malicious Markdown/XML/links/images, invalid relay events, length/MAC failures, URL credentials/query handling, archive traversal and duplicatepaths. Audit that no view or log exposes secrets, raw behavioural history is not in telemetry/crash reports, plaintext drafts are not in prefs/unprotected databases and clipboard exports are explicitly requested. Reject current-document proof on any exact-byte mismatch.

Review entitlement/build settings in the archive: Sandbox/HardenedRuntime on, no disabled libraryvalidation/get-task-allow release setting, no unnecessary network/mic permission, no development fixturekeys/model approval bypass. Check all vendored and SwiftPM licenses/notices, generated audio ownership and no bundled proprietary font files. Generate dependency/SBOM inventory and exact release source/artifact digests.

## Distribution and operations without a backend

Produce reproducible build/archive scripts, Developer ID signed app, signed DMG, notarization submission/acceptance and stapling validation. Use the owner's established signing identity/Keychain/CI secret configuration; never ask to paste credentials into a prompt or invent an Apple Team ID. Verify with codesign, spctl, stapler and an actual downloaded/quarantined clean-user install. Include both required architectures and test on supported Intelmac14–26 plus AppleSilicon minimum/currentOS, with evidence rather than build-only claims.

No store submission, payment system, hosted HWP evaluator or automatic self-updater is required. Provide Help→Check for Updates opening the public release page, no silent executable download. Document local data locations, backup/restore, permission repair, key-loss effects, offlinemode, Nostr server independence and uninstall. App deletion does not delete ordinary documents. An explicit erase-private-data command is scoped and confirmed; HWPpublishedproofs/relaydrafts cannot be promised universally erased.

Owner-held signing credentials and external provider test accounts are genuine release blockers if absent. Complete implementation/tests/buildscripts and record exact remaining action, but keep the corresponding acceptance rows BLOCKED and do not assert MVP complete. No second softer definition is allowed.

## Final handoff and exit

Produce `product/mac/evidence/RELEASE.md` and `RELEASE.json`: releasecommit, artifactSHA256, testedOS/hardware matrix, all60acceptance rows, actual commands/logs, screenshots, notarization IDs, privacy/license review and any nonblocking known limitations. No mandatory row remains blocked/skipped. Preserve frozenprotocolfiles/pins and preparationtests. Cross-check claimed features against the running release app, not source search alone.

Commit the integrated source and documentation, tag the release only after all mandatory gates pass and attach the signed DMG/checksums to the owner-approved release workflow. The deliverable is complete when a new user can install, write, save/recover, focus safely, export, publish/draft on Nostr and inspect/verify HWP honestly without a development toolchain or company backend. Scientific approval of a human-detection profile remains a separate process, never a fabricated part of a software release.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-08.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-08.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
