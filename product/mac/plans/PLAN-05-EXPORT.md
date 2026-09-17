# PLAN 05 — polished preview, PDF, DOCX and portable archives

> Recovered historical preparation; read the [current recovery notice](../RECOVERY-NOTES.md) before relying on source availability or test claims.

## Outcome and entry

From accepted Stage04, implement the complete source-to-document experience. Own **M30–M35**. Read EXPORT, DATA, UX U09, HWP's source-binding rules, fixtures/export-torture.md and SECURITY. The deliverable is actual polished artifacts that open correctly elsewhere, not a print dialog wrapped around a WebView or HTML renamed `.docx`.

## Recovery entry adjustment

The original fixtures/export-torture.md was not supplied. Create it from EXPORT.md with deterministic semantic expectations before renderer implementation, then add the required image and long-document fixtures. Do not treat an absent historical fixture as waived coverage.

## One semantic document, multiple renderers

Implement an immutable ExportSnapshot that binds source bytes/revision, selected template/page size, metadata, owned assets and any verified public proof. Parse into one versioned semantic representation shared by preview, PDF and DOCX. Support the explicit CommonMark/table/footnote/image/link subset in EXPORT. Unknown constructs produce a visible warning and literal-safe output where possible, not silently dropped text. Disable raw HTML execution and remote asset fetching. File paths, image dimensions, link schemes and archive names are untrusted.

Do not use rendered text as the new HWP source. The exact Markdown source remains the certified object where a proof exists; transformations into typesetting are separately described. Metadata titles, page headers and generated bibliography labels cannot quietly be included in a source-only HWP claim. Source and formatted outputs share content meaning, not necessarily identical bytes or identical pagination.

Implement Editorial and Manuscript templates with explicit page settings, font fallbacks, spacing, heading hierarchy, figures/captions, quotation treatment, lists, code, tables and footnotes. Default page size follows locale with a persistent explicit A4/Letter override. Use system-installed legally available fonts; no font file redistribution. Embed only fonts whose rights/OS APIs permit it, otherwise retain an honest fallback. Templates are data-driven internal constants, not a third-party plugin system.

## PDF pipeline and preview UI

Use CoreText/CoreGraphics to layout paginated PDF, with PDFKit for preview/print of the exact generated PDF bytes. Implement measured line breaking, baseline spacing, widow/orphan handling, heading-with-following-content, nonbreaking short list prefixes, paragraph/table splitting, repeated table headers, bounded image scaling and multi-page footnotes. Very long unbroken strings and code blocks must not disappear off the page: apply the documented wrap strategy and warning, preserving source.

Export searchable/selectable text with working hyperlinks, outline/bookmarks for headings and appropriate document metadata. Do not claim PDF/UA accessibility or archival PDF/A without actual conformance validation. Provide useful logical order and readable output anyway. Print consumes the same PDF output as preview. Cancelled exports leave no misleading completed file; failed writes retain the chosen source and can retry safely.

Build U09: Preview toggle/sheet with page thumbnails, zoom/fit, template chooser, page size and Export PDF/Export DOCX/Print. Large generation shows cancellable progress while the editor remains usable. The displayed preview identifies its source revision; an edit during generation invalidates the preview rather than silently presenting it as current. Choose output URLs through native panels and coordinate provider writes. Do not write temporary plaintext manuscripts into globally readable directories.

## Real OOXML DOCX

Generate a ZIP-based Open Packaging Conventions DOCX using the selected ZIP library and safely escaped XML. Include content types, relationships, document, styles, numbering, settings, core/app properties, hyperlinks, media and footnote parts as used. Headings use semantic paragraph styles; lists use numbering definitions; tables are real tables; emphasis/code/link semantics survive. Footnote IDs, rel IDs and image references must be consistent and deterministic for the same frozen export inputs except explicitly declared metadata timestamps.

Test the actual package rather than only XML well-formedness. Word and Pages must open without repair dialogs, retain all visible text and allow editing. A DOCX's pagination may vary with installed fonts and target application; the acceptance criterion is polished editable layout and complete semantic content, not a false PDF-pixel-identical promise. Include ordinary and large fixtures with nested lists, repeated footnotes, RTL paragraphs, diacritics, emoji fallback, multi-page tables and captions.

## Portability and proof companions

Implement source-only export, document archive and optional private-history export from DATA. A normal document archive contains exact source, safe asset paths, sanitized document/publication metadata and a public proof only if that exact snapshot has one. It excludes Keychain material, local paths/bookmarks, private histories, temporary logs and relay secrets. It must be recoverable by an independent unzip/text reader after the app disappears.

When exporting PDF/DOCX alongside a real source proof, include exact source and proof companions with a human-readable statement of what was certified. The export manifest may hash PDF/DOCX as products of this app, but is not an HWP certification of their rendering. Under the current empty production policy, no HWP file or badge is emitted. Nostr signatures are never shown as substitutes. Test an externally modified output and show that source-proof validity does not authenticate the altered rendered file.

Implement `.nwprivate` encryption/decryption with the exact DATA contract, separate random export key, bounded safe ZIP extraction, authenticated framing and no password-strength guesswork. Refuse missing/truncated/wrong-key/modified containers. The recovery UI must explain losing the separate key makes this export unreadable. Never automatically upload this file with the public document, to a relay or to a provider location not chosen for that action.

## Verification and exit

Automate text/structure extraction checks from generated files, archive path safety, entity escaping, invalid links, extreme image sizes, cancellation, failed provider writes and source-revision races. Make fixture generation deterministic and record input digests. Add golden metadata/page metrics where stable, with visual review rather than blind image threshold updates.

Render every page of the torture fixture in both templates and both paper sizes. Inspect page images on Mac for clipping, blank accidental pages, isolated headings, orphan labels, font substitutions and footnote overlap. Open DOCX in Word and Pages and record exact versions/screenshots. Test Preview/print handoff, VoiceOver in export controls and all errors with keyboard only. Large-export work must not block typing.

Exit only when M30–M35 pass with actual PDF/DOCX files attached to stage evidence and no hidden missing feature. Do not add those generated build artifacts to source control except deliberate small golden fixtures. The next stage publishes the same exact source snapshot; export must not mutate it.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-05.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-05.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
