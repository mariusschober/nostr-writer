# Native implementation architecture and resolved decisions

## Platform and build

Build a macOS 14+ document application with Swift 6 language mode. The verified current baseline is Xcode 27 / Swift 6.4; the host requirement is macOS Tahoe 26.6+ [A01]. Stage 01 records the exact installed build and SDK, rather than inventing a build number. Target arm64 and x86_64 on operating systems that support those architectures; Intel runtime acceptance uses macOS 14–26, not macOS 27. Framework availability above macOS 14 is guarded and tested. Modern system controls/materials adopt current OS appearance without hand-drawn imitation of platform chrome.

Use a checked-in `mac/NostrWriter.xcodeproj` with shared schemes and local Swift packages under `mac/Packages`. The app is a regular Dock/menu/document application. AppKit owns NSApplication, NSDocument, NSWindowController and NSTextView; SwiftUI hosts library/inspector/preferences/sheets. Do not carry NostrShot's global LSUIElement/accessory lifecycle into the main product. Optional Quick Post is an NSPanel owned by the same app.

Use TextKit 2 explicitly. Do not access the editor's `layoutManager` property for drawing/measurement: that can switch it to TextKit 1 [A02]. Keep preview/PDF layout separate from editor layout. Avoid WebView/Electron/Tauri, bundled Python, web editors, a general plugin engine and an unnecessary cross-platform abstraction. The Python protocol remains a development oracle and research tool; release users install a native app, not a toolchain.

Direct Developer ID distribution, App Sandbox **enabled**, hardened runtime, notarized/stapled DMG. Required sandbox capabilities are user-selected file read/write, outgoing networking for opted-in Nostr, and microphone access only for optional dictation. Use security-scoped bookmarks for selected external folders/files. No Full Disk Access, Accessibility, Input Monitoring, Screen Recording, global event tap, kernel extension, privileged helper, daemon or auto-start login item is required. Do not weaken sandbox or signing settings because a test did not work; diagnose scope/bookmark/entitlement handling. [A03–A05]

## Components and ownership

| Component | Responsibility and execution ownership |
|---|---|
| WriterDocument / DocumentSession | `@MainActor`; one live NSTextStorage, exact UTF-8 snapshot, current revision, undo state, active window; owns edits, not network tasks |
| EditorMutationGateway | `@MainActor`; native events, prechange delivery, postchange mutation, declared assistance source, actual selection; the only application mutation route |
| DocumentStore actor | Serialized SQLite metadata/recovery/history indexes and encrypted chunks; no synchronous database or cryptography on key event handlers |
| FileLifecycleCoordinator | NSDocument's file lifecycle plus external File Provider events; immutable read/write revisions, security scopes, conflict copies |
| HWP engine | Native deterministic library; closed release/model/protocol inputs, serial cancellable worker, no network, training or arbitrary supplied evaluator callbacks |
| ProofService actor | Finalization, exact source/proof pairing, production trust selection, guarded issuance and independent verification; never owns editor text |
| ExportService actor | Snapshot → Markdown AST/semantic intermediate representation → PDF/DOCX/archive; cancellation and progress; generated output never edits the source |
| NostrIdentity actor | Keychain operations and signing/decryption; secrets never leave service APIs as ordinary view state |
| RelaySession actors / NostrCoordinator | One socket per selected relay, bounded subscriptions, session-generation IDs, durable per-event outbox and remote draft conflicts |
| FocusSessionController | Pure reducer plus main-actor AppKit presentation adapter, watchdog/restoration, document binding; unrelated to HWP inference |
| SoundEngine | Native AVAudioEngine/AVAudioPlayer, local assets, interruption handling, no network or recording |

Packages: `WriterFoundation` (prepared pure contracts), `WriterStorage`, `WriterHWP`, `WriterExport`, `WriterNostr`. Platform adapters/UI live in `mac/NostrWriter/`. Do not create a package for every class. Foundation never imports UI or relay code. HWP does not import Nostr. Nostr can reference a proof digest but cannot grant human status. File Provider callbacks never write directly into NSTextView.

The editor is the live source of truth, not a SwiftUI `String` binding fed back on every render. An immutable `SourceSnapshot` contains document UUID, monotonic local revision, exact UTF-8 bytes and SHA-256. Every async result identifies its input snapshot. A stale result may be archived for that old revision but never replace current editor state, current proof state or the saved indicator. Actor boundaries use Sendable value types; no broad `nonisolated(unsafe)` to silence races.

## Essential interfaces

Implement the following names/contracts; signatures may become async where isolated, not change their semantics:

```swift
@MainActor protocol DocumentEditing {
  var snapshot: SourceSnapshot { get }
  func apply(_ command: EditCommand) throws
  func finalizeObservation(reason: ObservationBoundary) async throws -> CapturedRecordHandle?
}
protocol DocumentPersistence: Sendable {
  func persist(_ batch: RecoveryBatch) async throws -> DurableRevision
  func recover(_ id: DocumentID) async throws -> RecoveryState
}
protocol ProofChecking: Sendable {
  func assess(_ input: AssessmentInput) async -> AssessmentResult
  func verify(_ input: VerificationInput) async -> ProofResult
  func issue(_ input: IssuanceInput) async throws -> VerifiedProofArtifact
}
protocol DocumentExporting: Sendable {
  func render(_ snapshot: ExportSnapshot, format: ExportFormat) async throws -> ExportArtifact
}
protocol NostrPublishing: Sendable {
  func enqueue(_ intent: PublishIntent) async throws -> OutboxID
  func retry(_ id: OutboxID) async throws
  func observe(_ id: OutboxID) async -> AsyncStream<DeliveryState>
}
```

`issue` must fail unless the actual v0 producer, exact source/scope and independently admitted empirical release all pass. `ProofResult` is richer than an enum: it carries outcome, execution mode, claim, exact scope, policy pin, identities and limitations. The public human badge is derived from that value plus exact-current-bytes equality, never from “has a signature”. The prepared Foundation gate tests this rule; it is not the verifier.

## Dependencies and nondependencies

Reuse NostrShot's pinned libsecp256k1-backed P256K (0.23.2) and KeyboardShortcuts (3.0.1) as inspected baselines, preserving exact revisions from its Package.resolved [R02]. Harden/adapt them in Stage 06. Do not add a second secp implementation through an entire Nostr SDK merely for NIP-44.

Use CryptoKit for SHA-256, HMAC/HKDF, local AES-GCM and private Ed25519 signing. V0's strict public-point/subgroup checks remain mandatory; CryptoKit verification alone is not assumed to enforce all frozen encodings. Use `attaswift/BigInt` for exact integer/reference arithmetic where 64-bit overflow is possible. Python floor division of negatives is not Swift truncating division: provide and test explicit floorDiv/rounding helpers.

Use `swiftlang/swift-markdown` for CommonMark parsing, a narrowly specified footnote/table extension in the semantic layer, and `weichsel/ZIPFoundation` for OOXML/archive containers. Use the MIT Swift NIP-44 reference for composition of primitives, adapted to existing P256K and the current extended length prefix; CryptoSwift's IETF ChaCha20 is the additional primitive dependency, not CryptoKit ChaChaPoly as a substitute. [N03, N04] Stage 01/06 resolves and records exact reviewed release revisions, licence files and transitive pins. Dynamic branches, binary packages fetched at runtime, homemade signing/cipher primitives and `from:`-only unrecorded dependency state are forbidden. Version selection within these named dependencies is a routine build decision with tests, not an invitation to redesign the architecture.

Use system SQLite with one actor-owned connection and transactional prepared statements. No CloudKit database, Google API or custom sync scheduler. Use NSDocument/File Provider coordination for user documents [A04,G01]. Internal storage is in the app container. The app's installation key, Nostr key and any HWP role keys are separate key types and Keychain services.

## Failure containment

On capture failure: preserve editor text; end the affected record honestly; show recording interruption/NOT PROVABLE. On storage failure: stop claiming Saved, retain dirty text, stop accumulating an unbounded log, allow Export Recovery; do not block or discard human writing. On proof failure: retain old proof attached to its exact old source, mark current revision unproven. On relay failure: retain the exact signed event and per-relay state in the durable outbox. On focus failure: restore presentation options and release shields; data safety outranks blocking. On malformed remote/imported files: reject within bounds without running code, fetching URLs or creating files outside selected destinations.

The app may use cooperative cancellation and explicit worker bounds to protect responsiveness. A timed-out proof is unfinished/NOT PROVABLE, never evidence of an AI document or a successful research rejection. No resource limitation permits a different HWP computation to masquerade as the pinned one.
