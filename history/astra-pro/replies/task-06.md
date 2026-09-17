## Task 6

Prepared the Mac MVP handoff: eight detailed implementation PLANs, eight short START prompts, the product and interaction specifications, 60 mandatory acceptance criteria, and a tested Swift foundation package.

GitHub publication is incomplete. Some supporting objects and documents were uploaded, but I did not complete the commit and branch update. The remote repository must not yet be treated as the completed handoff. The prepared files are available below.

Implementation handoff index · 
Product contract · 
Native architecture · 
Complete UX specificationReader

The implementation sequence

Each PLAN specifies prerequisites, concrete implementation work, interaction details, failure handling, tests, owned acceptance criteria, and the evidence required before the next stage starts. Each START merely launches its corresponding PLAN from the current accepted repository state.

Stage	Implementation outcome	Detailed PLAN	Short START
1. Foundation	Recover the exact frozen protocol; audit NostrShot reuse; create the native document app, packages, build configuration and test infrastructure.	
PLAN 01	
START 01
2. Documents	Exact Markdown files, coordinated saves, encrypted recovery/history, selected cloud folders, conflict preservation and private archives.	
PLAN 02	
START 02
3. Editor	The complete long-form writing experience: TextKit editing, outline, find/replace, focus, assistance attribution and passage inspection.	
PLAN 03	
START 03
4. Human Writing Protocol	Actual native algorithm and proof execution, observation boundaries, policy handling, offline verification and truthful proof states.	
PLAN 04	
START 04
5. Export	Shared document interpretation, polished paginated PDF, editable DOCX, preview and source-proof companions.	
PLAN 05	
START 05
6. Nostr	Key management, durable publication, long-form revisions, Quick Post, encrypted NIP-37 drafts and relay failure recovery.	
PLAN 06	
START 06
7. Discipline	Voluntary locked sessions, clipboard restrictions, multi-display shields, emergency release and local ambient audio.	
PLAN 07	
START 07
8. Release	Integrated journeys, accessibility, performance, security review, signed/notarized distribution and final acceptance.	
PLAN 08	
START 08
Decisions that remove implementation ambiguity

The product is a native document editor, not an expanded menubar composer. The chosen foundation is AppKit’s document architecture and a TextKit 2 editing surface, with SwiftUI for supporting interface elements. NostrShot contributes relevant signing, key-management and relay work; its application shape is not retained. Quick Post becomes an optional, separately recovered panel.

Documents remain ordinary Markdown files. Titles, publication metadata, history and provenance live in a private catalogue rather than being silently inserted into frontmatter. Local, iCloud Drive and Google Drive Desktop locations use the same user-selected filesystem workflow. The plans distinguish a successful file write from confirmed cloud replication and require preserving both versions before resolving conflicts. 
Storage specification

Assistance remains usable without receiving unearned provenance. Spellcheck, grammar changes, predictions, dictation and translated text have explicit origins. Their presence does not make the product “anti-AI”; equally, known provenance does not automatically make assisted wording fresh human composition. The frozen protocol’s current rules remain authoritative. 
HWP integration contract

Software-only Mac capture is not presented as independently trusted physical input. The application journal and the HWP-admissible observation record are separate. Agents must implement the actual native algorithm and joined proof verification, including positive conditional conformance cases—not an always-negative placeholder. Production approval remains empty until the necessary empirical and capture evidence exists. Consequently, the MVP can be a complete writing product without falsely claiming that real certification is already available.

Locked writing is voluntary discipline, not device security. The specification requires public APIs, tested presentation restrictions, optional neutral shields on other displays, and a visible keyboard-accessible emergency release. It excludes privileged helpers, system-wide keylogging, killing other applications, or preventing Force Quit. Storage failure releases restrictions rather than trapping the writer with unsaved work. 
Focus contract

Exports share one semantic document model. PDF is selectable-text, paginated output; DOCX is genuine editable Office Open XML. The plans define templates, footnotes, tables, images, pagination, asset limits and actual Word/Pages checks. A source HWP is exported as a clearly explained companion—it does not silently certify the rendered PDF or DOCX. 
Export specification

Nostr publication is durable before it is fast. Publication intent is persisted before signing, and the exact signed event is persisted before transmission. Retries reuse identical bytes. Relay acceptance, partial failure and draft restoration have explicit states. Long-form article identity, encrypted draft identity and immutable event IDs remain distinct. 
Nostr specification

The NostrShot audit also identifies concrete changes agents must make: whole-URL lowercasing/query removal, an acknowledgement-registration race, Keychain errors treated as missing keys, and RAM-only pending publication behaviour. These are recorded as source-inspection findings with required regression tests, not claims that a native build was exercised here. 
Repository audit

Foundational work already executed

The preparation includes a small WriterFoundation Swift package rather than a premature application implementation. It covers exact source-byte revisions, Unicode offset conversion, neutral proof-state presentation, relay URL preservation, replaceable-event ordering, NIP-44 length arithmetic and pure focus-session state.

47 portable Swift tests pass. The preparation/bootstrap suite adds 10 passing tests. The frozen joined HWP input was recovered, its 178 tests were rerun successfully in bounded groups, its independent verifier passed, and regenerated interoperability vectors matched the frozen file exactly. 
Preparation evidence · 
Machine-readable results · 
Foundation package guide

A verified source transport and bootstrap were prepared because the remote repository did not contain the complete joined frozen v0 package. The bootstrap restores the original source and regenerates its deterministic vector without changing the freeze manifests. 
Frozen-input instructions · 
Bootstrap script

No native Mac application build, AppKit interaction, VoiceOver session, actual cloud-provider conflict, Word/Pages export review, multi-display lock test or notarization was performed in this preparation. Those are mandatory implementation-stage gates, not inferred from portable tests.

One definition of completion

The Mac MVP is complete only when all 60 mandatory criteria pass on the same candidate commit, all eight stage handoffs contain actual execution evidence, and a Developer ID–signed, notarized, stapled DMG passes a clean-user installation and end-to-end Mac acceptance run.

Missing signing credentials produce a blocked release—not a claim that an unsigned development ZIP is complete. Unvalidated HWP components cannot produce real certification; conversely, the empty production policy cannot excuse failure to implement and test the real verification paths.

Definition of complete · 
All 60 acceptance criteria · 
Module interfaces · 
Security requirements

The remaining deficiency in this assignment is publication, not the preparation artifacts: the complete prepared tree still needs to be committed and attached to the repository branch before START 01 can be handed to an agent with the repository alone.