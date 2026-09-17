# Product contract

> Recovered historical preparation; read the [current recovery notice](RECOVERY-NOTES.md) before relying on source availability or test claims.

## The product and the primary journey

Nostr Writer is a native writing environment that protects human thinking by making the human formulate the text. It is neither an AI-content detector nor an AI prohibition tool. Research, discussion and AI-assisted understanding may precede writing. Mechanical transcription remains a negative experimental case for HWP even when every character was physically typed.

The default journey is: launch without an account → open or create a Markdown document → write in a quiet editor → optionally enter a disciplined session → preview/export a polished document → optionally connect Nostr and publish. Recording, remote draft sync, Nostr identity and proof review must not interrupt typing or be prerequisites for ordinary writing. There is no startup dashboard of authenticity scores, token usage or gamified streaks.

The primary window is a normal document window, not NostrShot's menu-bar panel. Optional Quick Post retains NostrShot's speed as an auxiliary feature with its own durable draft. Long-form documents are retained after publication. Publishing is an operation on an immutable revision, not a destructive transition that empties the editor.

## Included in the Mac MVP

Native plain-text Markdown editing; multiple documents/windows; recents/library, outline, find/replace, native undo/redo, sentence/paragraph focus and typewriter scroll; local autosave/recovery and selected Finder locations, including iCloud Drive and Google Drive for desktop; local provenance/history controls; complete native HWP conditional producer and V/R verifier; exact-source proof files and voluntary evidence disclosure; two polished PDF/DOCX templates, preview and print; local/relative images, tables and footnotes; Nostr identity, kind-1 Quick Post, kind-30023 long-form publication, persistent outbox, NIP-37 draft wraps/private relay list, NIP-44 encryption and NIP-42 authentication; optional time/word-goal sessions with copy/paste and environment restrictions; four offline sounds; accessible settings/help; signed, notarized direct distribution.

One connected Nostr identity at a time is sufficient. Switching identities is explicit and never reassigns old outbox items or drafts. A read-only npub can be displayed but cannot publish/decrypt. No wallet, token, paid relay purchase, company account or subscription is required.

Not in this MVP: Android/iOS, cross-platform UI toolkit, collaborative CRDT, Google Docs editing, custom Google/iCloud sync backend, cloud history service, social feed, payments, automatic AI generation, external signer/bunker support, web publishing CMS, custom proof hosting, automatic update framework, system-wide security enforcement, privileged helper, ZK prover, C2PA authoring or a new HWP algorithm. These are exclusions, not unfinished mandatory controls.

## Proof claim and release posture

The intended explanatory claim is: “The selected text has an observed composition history accepted under the identified Human Writing Protocol release and trust policy.” In attested mode it is an assertion by admitted evaluators; disclosed mode also recomputes the history. The description must identify exact scope, fresh-composition versus wording-origin, execution basis and evidence limitations. Do not advertise cryptographic certainty about cognition or an undetectable absence of all injection.

NOT PROVABLE covers absent approval, insufficient/unsupported observation, imported wording, failed bindings and non-admission. It never means AI-written. No HWP signature is issued for that outcome. A Nostr signature only signs a Nostr event; ordinary Markdown/PDF/DOCX export remains available regardless of proof status.

The current freeze has no production-approved model or Mac capture path. This release is therefore a fully usable Writer MVP with experimental local composition records and honest HWP availability. The implementation must not invent a permissive model, treat a user's local signing key as evaluator authority, relabel real observations as evaluated capture, or market the shipped product as scientifically validated. The completion gate requires the correct negative production state plus actual conditional conformance execution. Empirical certification activation is a separately evidenced future release, not a coding-agent discretion.

## Assistance and externally sourced wording

Spellchecking/grammar *indications* do not change wording and may be enabled. Applying a correction, inline completion, dictation, translation or generated rewrite is a distinct attributed mutation. Known provenance makes the workflow understandable; it does not automatically make that output a qualifying v0 human-composed span. Frozen v0 removed automatic spelling inheritance, including tiny edits such as `100 → 900`.

Default Write mode: spellcheck indications on; automatic replacements/completion/smart punctuation and Apple Writing Tools off; no generated text. An explicit Assistance preference can enable tracked correction commands and optional on-device dictation. Unsupported opaque OS transformations remain usable only with an explicit provenance interruption/unsupported range, never fabricated direct-input evidence. Translation/generative external text may be inserted through an explicit “Insert external text” operation with source description. There is no built-in AI service to configure.

Quotations and citations are first-class source annotations. Selection → Mark as quotation/external source records a source description and byte range; it does not certify nearby words or select new evidence windows. Unmarking removes the presentation annotation, not the immutable origin. A person can genuinely write new wording after reading an external source; no semantic contamination rule follows that idea forever.

## Defaults and limits

Default document: exact UTF-8 `.md`, new line LF, no hidden front matter or automatic trimming. Existing CRLF/BOM/Unicode sequences are preserved; imports needing conversion require an explicit preview and create a new unproven revision. Default editor: system monospaced 18pt, comfortable 72-character measure, line height about 1.5, wide margins, spellcheck indications on. Native appearance follows system; users can choose font family/size/measure and light/dark/system. No font file is redistributed without a proper licence.

Recording is explained once with explicit consent: “Store writing history on this Mac, including deleted text.” Start Writing with Recording and Write Without Recording are equally usable actions. Recording can be paused or disabled later. Sounds, menu-bar Quick Post, remote drafts and strict sessions are off by default. Nostr is connected only on user request.

Editor hard input bound: 8 MiB and 1,000,000 Unicode scalars; opening larger files offers read-only inspection/export, never truncation. Native HWP retains its stricter limits (200,000 scalars/1 MiB document and its evidence bounds). Crossing them stops eligibility, not ordinary writing. Nostr draft plaintext is capped at 1 MiB in the app; websocket/event input at 2 MiB; relays may impose smaller limits. Exceeding a network limit leaves the local document untouched and offers explicit export or smaller publication, never silent splitting/truncation.

## Non-negotiable behavioural design

The UI must make writing the easiest action. No live human-percentage gauge, no requirement to make mistakes, no reward for artificial pauses, no rewriting to satisfy a detector and no claim that a focus session proves authorship. HWP review is an explicit secondary operation. Evidence remains local unless the user deliberately exports or discloses it. Every destructive or public action has a precise scope; first public publication gets a clear confirmation, subsequent configured publication can be one click.
