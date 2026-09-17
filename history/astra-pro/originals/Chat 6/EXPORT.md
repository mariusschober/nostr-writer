# Export and preview contract

## Source fidelity and one semantic model

Take one immutable ExportSnapshot: exact source bytes/revision/digest, document metadata, template/paper options, explicitly accessible image bytes and optional matching source proof. Parse once into a semantic intermediate representation using swift-markdown CommonMark plus the exact supported footnote/table extensions. PDF, DOCX and Preview consume that same representation. The parser/renderers never edit source bytes, normalize whitespace, fetch URLs or change proof scope. Preserve soft/hard linebreak semantics according to Markdown, not visual source wrapping.

Required blocks: paragraphs, ATX/Setext headings1–6, ordered/unordered/nested lists, task-list display, blockquotes, fenced/indented code, thematic rules, tables, footnotes and local images with alt/caption. Required inline: emphasis/strong/strikethrough, inline code, escaped punctuation, links, explicit linebreak and Unicode bidirectional text. Footnotes use `[^id]` references and definition blocks; tables use a header separator row and pipe cells with escaped-pipe handling. Literal unsupported raw HTML is rendered as literal text or clearly warned, never executed. Disallow JavaScript/data/file URL links in exported hyperlinks; ordinary HTTPS/mailto links remain real clickable links. Code preserves indentation and wraps/continues without clipping; line numbers are not injected by default.

Document title is optional export metadata; if enabled it appears once in front matter, not duplicated by auto-removing an author's first heading. The user can disable title page/header. A template may not secretly delete the first heading to avoid visual repetition. Metadata is outside source HWP unless present in source.

## Two complete templates

**Editorial (default).** A4 or Letter, 22mm margins; Georgia body11pt/15.5pt baseline; system sans headings (H1 24pt, H2 18pt, H3 14pt, remaining12pt bold); text near-black, restrained accent on links; paragraphs 5pt after, no first-line indent; code system mono9pt/12pt on a subtle semantic grey with sufficient contrast; blockquote left rule/indent; tables9.5pt minimum with repeatable header and modest cell padding; captions9pt; footnotes9pt. Running footer page number; optional short title in header after first page. No ornamental cover imagery or fake imprint.

**Manuscript.** Same paper choices, 25mm margins; system monospaced11pt/18pt, headings visibly distinct, paragraphs separated by6pt, monochrome, running short title/page number, minimal rules. It must look intentionally typeset, not an unstyled browser printout. Template dimensions are independent of editor font/zoom.

Default paper derives only from locale (US/Canada Letter, otherwise A4); settings always expose both. Explicit export options override locale and persist per document. Fonts use installed system fonts/fallbacks; do not copy/ship Apple or iA font files. Georgia availability is tested; when unavailable use documented installed serif fallback and show a preview warning. PDF glyph fallback must handle the multilingual fixture. Embedding by the platform's ordinary PDF export mechanism is not a licence to distribute font files.

## PDF/Preview/Print

Use CoreText/CoreGraphics pagination and PDFKit preview, not a screenshot of NSTextView or a WebView print shortcut. Preserve selectable/searchable text, links, document metadata, heading outline, page numbers, repeatable table headers and footnote-to-reference destinations. Keep headings with at least two following lines, avoid single-line widows/orphans where feasible, prevent clipped tables/code/images, scale images within page bounds while preserving aspect ratio, and handle long unbreakable URLs. When a block cannot fit, apply a documented continuation/wrapping rule, never drop it. A very long table row can split across pages with clear continuation, not overflow off-page.

Footnotes are placed at page bottom with a separator; the page-flow algorithm reserves their measured space and repeats layout until stable with a bounded fallback to a labelled continued footnote. Preview shows the *same generated PDF bytes* that Export/Print use for that snapshot. Editing invalidates preview; stale rendering may be displayed with a source-revision label, never exported as current without refresh.

Prefer tagged PDF/accessibility structure supported by the chosen native drawing pipeline; at minimum supply reading-order logical content, selectable Unicode text and navigable outline. Do not falsely label the output PDF/UA compliant without an actual validator/audit. Accessibility of the editor and exported semantic DOCX remains mandatory independently of that optional certification.

## DOCX

Create a real Office Open XML ZIP package using ZIPFoundation: [Content_Types].xml, _rels/.rels, word/document.xml, styles.xml, numbering.xml, footnotes.xml when used, document relationships, media and properties. Escape XML correctly; preserve `xml:space` where needed. Use semantic Heading1–6, Normal, Quote, Code, Caption, TableHeader, List styles, real numbering definitions/levels, hyperlinks with relationships, true footnote references and images with descriptions. Use sections for paper/margins and PAGE fields in footer; add widow/keep-next rules. Do not fake a DOCX by renaming RTF/HTML and do not rasterize the document.

Word and Pages may repaginate because they use their own layout engines; promise semantic/template consistency, not pixel-identical PDF/DOCX pagination. Open the result in Word and Pages when available, inspect styles/outline/tables/footnotes/images and exercise edit→save→reopen. Automated XML/ZIP validation plus one viewer is not sufficient to claim both viewers tested. Stage08 tracks unavailable owner-licensed Word as an explicit unpassed interoperability gate, not a silent pass.

## Companion proof and portability

V0 certifies exact Markdown, not transformed PDF/DOCX. Exporting with a proof produces a companion directory/ZIP containing exact source.md, source.hwp, output.pdf or output.docx, and export-manifest.json with source/output SHA-256+sizes, renderer/template version and snapshot identity. The manifest is descriptive linkage, not a new HWP-signed claim of rendering equivalence. Never embed an unqualified HUMAN-WRITTEN seal inside a transformed document. Optional small footer says “Source Markdown has a scoped Human Writing Proof; see accompanying source and proof” only when true and with its scope. NOT PROVABLE produces no HWP companion or seal.

Exporting ordinary files always works without HWP/Nostr. Source ZIP uses DATA.md's safety rules. Proof/detailed evidence export checks exact matches, bounds and consent. Cancellation removes only app-owned temporary files. Any existing destination overwrite uses native confirmation; write a temporary sibling then atomically replace. A source changes during export → export remains labelled that earlier snapshot and UI offers Refresh, never accidentally pairs its proof with newer bytes.

## Acceptance fixtures

`fixtures/export-torture.md` is mandatory: multi-level headings, typography, nested lists, blockquotes, multilingual/decomposed text, long URL, code, table, footnote, image placeholder, missing-asset/error cases and an explicit external quote. Stage05 adds generated local test images with known dimensions and a15000-word long fixture. Store source digests and semantic expected counts, not brittle platform-font byte-identical PDF hashes. Automated checks inspect page bounds/links/text/OOXML structure; render every PDF page to images and visually inspect representative plus edge pages (or contact sheets plus full failing pages). Never claim visual verification from XML/text extraction alone. Stage08 captures native Preview/PDF/Word/Pages screenshots on the exact release commit.
