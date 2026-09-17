# PLAN 03 — focused long-form UX and provenance-aware input

> Recovered historical preparation; read the [current recovery notice](../RECOVERY-NOTES.md) before relying on source availability or test claims.

## Outcome and entry

From accepted Stage02, deliver the finished writing experience and truthful local observation model. Own **M14–M21**. Read UX in full, PRODUCT, DATA, HWP and FOCUS's mutation restrictions. Inspect the frozen telemetry/replay contracts before implementing event capture. This stage does not approve a Mac capture authority, train a model or create positive HWP certificates.

## Native editor implementation

Replace the temporary editor with explicitly initialized TextKit 2 NSTextView and native text input/undo behaviour. The view/text storage owns the live text. SwiftUI observes snapshots and sends explicit commands; it must not write an old String binding back during a render. Keep layout and syntax decorations out of the source string. Do not access the old `layoutManager` centering code copied from NostrShot. Long-form text is top-aligned with generous insets, configurable reading measure and continuous smooth scrolling, not a vertically centered menu-bar note.

Implement the exact UX layout: centered 72-character default measure, 18-point system monospaced editor, 1.5 line-height target, native semantic colors, optional sidebar and inspector, restrained status line. Support system light/dark, font size 13–32, increased contrast and Reduce Motion. Use native font/menu controls rather than shipping a proprietary iA font. Paragraph focus and typewriter scrolling are optional toggles; they cannot dim text below accessibility contrast or move the cursor unexpectedly. A Focus toggle hides chrome but Escape exits ordinary focus immediately.

Implement Markdown source editing with syntax emphasis as attributes, headings/outline, inline code, fenced blocks, lists, links, blockquotes, thematic breaks, images, tables/footnotes supported by EXPORT's grammar, find/replace and navigation to headings. Formatting commands insert visible Markdown syntax through the same mutation gateway; automation used to insert syntax is recorded as such rather than called direct physical typing. Unsupported Markdown remains editable source and has an explicit export warning later. No word-completion suggestions, AI chat or generative rewrite pane is added by default.

Word/character counts and selection counts are informational, not a human score. Use stable natural-language word segmentation for product counts, distinct from HWP scalars/roots. Outline updates are cancellable and revision-bound; a parser finishing for an old snapshot cannot replace the current selection. Keyboard shortcuts and menus are as specified in UX; maintain native undo grouping and selection. All actions have accessibility names and full keyboard reachability.

## Mutation and observation boundary

Create EditorMutationGateway around actual input delivery, text storage before/after state, selection, focus and declared app operations. Maintain UTF-16/native offsets, Unicode scalar indices and UTF-8 byte ranges explicitly using the prepared coordinates tests. IME marked-text composition, dead keys, emoji, combining accents, autocorrection, drag/drop, Services, accessibility insertion, dictation and programmatic restore are different causes. Do not infer physical input from one-character transactions or substitute missing key-up events. Do not count a lost-focus interval as thinking.

The app-level local journal may describe incomplete observations honestly. Export to frozen HWP telemetry only when every required field has an actually observed basis. Specifically, duplicating transaction data into a supposed independently observed native-delivery field is not evidence. App-owned software observations cannot be labelled an evaluated HWP capture profile by declaration. Missing or opaque origin becomes unknown/unsupported; the user can keep writing normally.

Every mutation changes the exact revision. Copies/moves/undo retain root ancestry in the local provenance model; deletion retains history only with recording consent. Cut/paste inside a document requires an app-issued private source token plus exact live data equality, otherwise it is external paste. Cross-document import references a real source record when available; never infer provenance merely from identical text. External change/recovery boundaries remain unobserved imports unless a genuinely compatible parent capture exists. App-specific journals and HWP canonical files have separate version identifiers.

Freeze a capture release/profile at each eligible observed run's start, never when choosing an accepting model later. Changes of input path, recording consent, gaps, app restart or release change create boundaries. Native OS events can be quantized/captured at their actual available resolution only. Resource limits pause detailed capture and explain the gap while preserving normal text editing/recovery.

## Transparent assistance and quotation UX

Implement proofreading affordances without claiming new wording is direct composition. Native spelling/grammar indications may be enabled; acceptance of a replacement is a known assisted mutation. Autocomplete, smart substitutions and Writing Tools mutation capability are off by default; the controlled recording mode disables Writing Tools where available and captures any unavoidable opaque change as unknown. On macOS versions without that API, do not pretend a setting exists. The product can allow known assistance in ordinary mode, but current HWP may leave the changed span NOT PROVABLE.

Implement on-device dictation as an explicit command only when the system/language supports it. Request mic/speech permission at invocation, use a stable insertion anchor and replace only the active dictated range. Other typed text is never overwritten by an asynchronous transcript. Stop/cancel/error/wake/new document invalidate old callbacks with a generation token. Do not fall back to network speech silently. Mark dictated output known-assistance and explain current proof limits. Translation through system/Services can be used, but opaque output stays externally assisted; do not create a bespoke translation API or network dependency.

Implement selected-range source annotation: quotation, citation/reference, external or assisted material with user-supplied label/URL. Markdown quote syntax alone is not proof of accurate attribution. An annotation excludes exact bound ranges from a selected-contribution claim, not the whole document or future replacements. Editing inside an annotated range must update its exact origin map or mark the annotation stale for review; it cannot shift a favorable exclusion over unrelated text. Inspector shows origin descriptions, capture gaps and current proof availability, not a red AI accusation or percentage human meter.

## Adversarial and UX verification

Automated tests cover 1000 random Unicode edits, undo/redo/move/copy, selection replacement, stale SwiftUI renders, late dictation updates, IME cancellation, emoji picker, pasted quotation, search/replace and external restore. Test blocked external insertion hooks for Stage07 without enabling global interception. Replay the journal after each operation and compare exact source bytes; malformed intervals return an explicit capture gap without corrupting text.

On real Macs exercise US/German layouts, dead keys, at least one IME, VoiceOver editing, spell correction, system dictation, Services and Writing Tools availability. Evaluate 100k-word documents for responsiveness, retaining evidence of actual timings. Take actual screenshots of all editor/inspector/annotation/error states at 760 and1120 widths, both appearances. A screenshot alone does not replace interaction and accessibility tests.

## Exit

All M14–M21 pass: the app is an excellent ordinary writing environment, supports required input methods and transparent assistance, preserves data, and records only what it actually observes. Stage04 receives real typed interfaces and fixtures, not a fabricated guarantee that software-only capture can authenticate a human source.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-03.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-03.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
