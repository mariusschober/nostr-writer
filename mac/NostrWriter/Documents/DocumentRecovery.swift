import AppKit
import Security
import WriterFoundation
import WriterStorage

/// Application-owned, injected private-store factory. File and key operations
/// stay on this actor; document windows never wait synchronously for it.
actor RecoveryLibrary {
    private var opening: Task<DocumentStore, Error>?

    init() {}
    init(store: DocumentStore) { opening = Task { store } }

    struct Prepared: Sendable {
        let source: SourceSnapshot
        let record: DocumentCatalogRecord
    }

    func prepare(_ source: SourceSnapshot, url: URL?, parent: SourceSnapshot?) async throws -> Prepared {
        let store = try await store()
        let location = url?.standardizedFileURL.resolvingSymlinksInPath().absoluteString
        var record: DocumentCatalogRecord
        var prepared = source
        if let location, let existing = try await store.catalogRecord(at: location) {
            record = existing
            switch try await store.recover(existing.documentID) {
            case .complete(let durable):
                if durable.source.utf8 == source.utf8 {
                    prepared = durable.source
                } else {
                    // Keep an unsaved prior revision as its own recovery entry
                    // before the newly opened file can supersede it.
                    if existing.savedDigest != durable.source.digest {
                        let copy = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: durable.source.utf8)
                        _ = try await store.persist(RecoveryBatch(source: copy, receipts: []))
                        var recovered = DocumentCatalogRecord(documentID: copy.documentID,
                            title: "Recovered \(existing.title)", parent: durable.source)
                        recovered.isOpen = false
                        try await store.saveCatalogRecord(recovered)
                    }
                    guard let next = durable.source.revision.next else { throw ContractError.unsupported("The document revision limit was reached.") }
                    prepared = try SourceSnapshot(documentID: existing.documentID, revision: next, utf8: source.utf8)
                }
            case .absent:
                let previous = Revision(existing.savedRevision ?? 0)
                guard let next = previous.next else { throw ContractError.unsupported("The document revision limit was reached.") }
                prepared = try SourceSnapshot(documentID: existing.documentID, revision: next, utf8: source.utf8)
            case .localPartial, .conflict, .corrupt, .keyUnavailable:
                throw RecoveryKeyError.unavailable("Existing recovery needs review. Your opened file remains editable and no recovery was replaced.")
            }
        } else if let existing = try await store.catalogRecord(for: source.documentID) {
            record = existing
        } else {
            record = DocumentCatalogRecord(documentID: source.documentID,
                                            title: url?.lastPathComponent ?? "Untitled", location: location, parent: parent)
        }
        if let url {
            record.bookmark = try await ScopedSourceFiles().bookmarkForExplicitSelection(url)
            record.savedRevision = prepared.revision.rawValue; record.savedDigest = prepared.digest
        }
        record.isOpen = true; record.isVisible = true; record.updatedAt = Date().timeIntervalSince1970
        _ = try await store.persist(RecoveryBatch(source: prepared, receipts: []))
        try await store.saveCatalogRecord(record)
        return Prepared(source: prepared, record: record)
    }

    func recordSave(_ saved: SavedFileRevision, parent: SourceSnapshot?) async throws {
        let store = try await store()
        var record = try await store.catalogRecord(for: saved.source.documentID)
            ?? DocumentCatalogRecord(documentID: saved.source.documentID, parent: parent)
        record.location = saved.url.standardizedFileURL.resolvingSymlinksInPath().absoluteString
        record.bookmark = try await ScopedSourceFiles().bookmarkForExplicitSelection(saved.url)
        if let newer = try await store.catalogRecord(for: saved.source.documentID),
           let revision = newer.savedRevision, revision > saved.source.revision.rawValue { return }
        record.title = saved.url.lastPathComponent
        record.savedRevision = saved.source.revision.rawValue; record.savedDigest = saved.source.digest
        record.isOpen = true; record.updatedAt = Date().timeIntervalSince1970
        try await store.saveCatalogRecord(record)
    }

    func catalogEntries() async throws -> [DocumentCatalogRecord] {
        let store = try await store()
        return try await store.catalogRecords().filter { $0.isVisible }
    }

    /// A separate recovery identity survives rolling-checkpoint compaction of
    /// the document that is about to be reverted or replaced.
    func preserveCopy(_ source: SourceSnapshot, title: String) async throws {
        let store = try await store()
        let copy = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: source.utf8)
        _ = try await store.persist(RecoveryBatch(source: copy, receipts: []))
        var record = DocumentCatalogRecord(documentID: copy.documentID, title: title, parent: source)
        record.isOpen = false
        try await store.saveCatalogRecord(record)
    }

    func markClosed(_ id: DocumentID) async throws {
        let store = try await store()
        guard var record = try await store.catalogRecord(for: id) else { return }
        record.isOpen = false; record.updatedAt = Date().timeIntervalSince1970
        try await store.saveCatalogRecord(record)
    }

    func recoveredEntries() async throws -> [DocumentCatalogRecord] {
        let store = try await store()
        let records = try await store.catalogRecords()
        let metadata = try await store.allDocumentMetadata()
        let orphans = metadata.filter { entry in !records.contains(where: { $0.documentID == entry.documentID }) }
            .map { DocumentCatalogRecord(documentID: $0.documentID, title: "Recovered document") }
        return (records + orphans).filter { record in
            guard record.isVisible, let latest = metadata.first(where: { $0.documentID == record.documentID }) else { return false }
            return record.savedDigest != latest.latestDigest
        }
    }


    func searchCurrentText(_ query: String) async throws -> [DocumentCatalogRecord] {
        guard !query.isEmpty, query.utf8.count <= 4096 else { return [] }
        let store = try await store()
        var result: [DocumentCatalogRecord] = []
        for record in try await store.catalogRecords() where record.isVisible {
            try Task.checkCancellation()
            if record.title.localizedCaseInsensitiveContains(query) { result.append(record) }
            // Search only the current source checkpoint. No deleted revisions,
            // detailed history, keys, or plaintext persistent search index.
            else if case .complete(let current) = try await store.recover(record.documentID),
               current.source.string.localizedCaseInsensitiveContains(query) { result.append(record) }
            if result.count >= 100 { break }
        }
        return result
    }

    func recoveredSource(_ id: DocumentID) async throws -> SourceSnapshot {
        let store = try await store()
        guard case .complete(let current) = try await store.recover(id) else {
            throw RecoveryKeyError.unavailable("This recovery needs review and was preserved unchanged.")
        }
        return current.source
    }

    func store(retry: Bool = false) async throws -> DocumentStore {
        if retry, let opening {
            do { return try await opening.value } catch { self.opening = nil }
        }
        if let opening { return try await opening.value }
        let task = Task { try await openStore() }
        opening = task
        return try await task.value
    }

    private func openStore() async throws -> DocumentStore {
        // UI automation uses isolated fixtures. It must never provision a key
        // or write into the normal user's private library.
        guard ProcessInfo.processInfo.environment["NW_TEST_DEFAULTS"] == nil else {
            throw RecoveryKeyError.unavailable("Recovery is disabled in this isolated interface test.")
        }
        guard let task = SecTaskCreateFromSelf(nil) else {
            throw RecoveryKeyError.unavailable("Recovery needs a valid application signing identity. Save a source file to keep writing safe.")
        }
        let groups = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) as? [String]
        let appID = (SecTaskCopyValueForEntitlement(task, "com.apple.application-identifier" as CFString, nil) as? String)
            ?? (SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil) as? String)
        guard let accessGroup = groups?.first ?? appID else {
            throw RecoveryKeyError.unavailable("Encrypted recovery is unavailable in this unsigned development build. Save your document to a file.")
        }
        #if DEBUG
        let environment = "Development"
        let service = "com.mariusschober.nostrwriter.development.recovery"
        #else
        let environment = "Release"
        let service = "com.mariusschober.nostrwriter.recovery"
        #endif
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let parent = support.appendingPathComponent("NostrWriter", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return try await RecoveryBootstrap().open(root: parent.appendingPathComponent(environment, isDirectory: true),
                                                  service: service, accessGroup: accessGroup)
    }
}

/// One bounded handoff per document, coalescing only replaceable source
/// checkpoints. It never holds detailed capture history or publish intents.
@MainActor
final class DocumentRecovery {
    private let library: RecoveryLibrary
    private let documentID: DocumentID
    private var coordinator: RecoveryCoordinator?
    private var latest: SourceSnapshot
    private var pending: SourceSnapshot?
    private var handoff: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var metadataHandoff: Task<Void, Never>?
    private var generation = UUID()
    private(set) var message = "Preparing recovery…"
    private(set) var hasFailure = false
    var didChange: (() -> Void)?

    init(source: SourceSnapshot, library: RecoveryLibrary) {
        self.latest = source; self.documentID = source.documentID; self.library = library
        attach(retry: false)
    }

    func observe(_ source: SourceSnapshot) {
        guard source.documentID == documentID else { return }
        latest = source; pending = source
        drain()
    }

    func retry() { attach(retry: true) }

    private func attach(retry: Bool) {
        let current = UUID(); generation = current
        monitor?.cancel(); handoff?.cancel()
        hasFailure = false; message = "Preparing recovery…"; didChange?()
        handoff = Task { [weak self, library] in
            do {
                let store = try await library.store(retry: retry)
                guard let self, current == self.generation else { return }
                if self.coordinator == nil {
                    self.coordinator = try RecoveryCoordinator(documentID: self.documentID, persistence: store)
                }
                self.pending = self.latest
                self.handoff = nil
                if retry { await self.coordinator?.retry() }
                self.drain()
                self.startMonitor()
            } catch {
                guard let self, current == self.generation else { return }
                self.handoff = nil; self.fail(error)
            }
        }
    }

    private func drain() {
        guard handoff == nil, let coordinator else { return }
        handoff = Task { [weak self] in
            guard let self else { return }
            while let source = self.pending, !Task.isCancelled {
                self.pending = nil
                do { try await coordinator.observe(source) }
                catch { self.fail(error); break }
            }
            self.handoff = nil
        }
    }

    private func startMonitor() {
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let coordinator = self?.coordinator else { return }
                let state = await coordinator.state()
                if let error = state.lastFailure { self?.fail(error) }
                else {
                    self?.hasFailure = false
                    self?.message = state.isDurablyRecovered ? "Recovery up to date" : "Recovery pending"
                    self?.didChange?()
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func flush(_ source: SourceSnapshot, boundary: ObservationBoundary) async throws {
        // An earlier boundary must not replace a newer pending edit while the
        // store is opening. The actor flushes its latest admitted revision.
        if source.revision >= latest.revision { observe(source) }
        await waitForHandoff()
        guard let coordinator else { throw RecoveryKeyError.unavailable(message) }
        do { _ = try await coordinator.flushLatest(atBoundary: boundary) }
        catch { fail(error); throw error }
        await metadataHandoff?.value
    }

    func acknowledgeSave(_ saved: SavedFileRevision, parent: SourceSnapshot?) {
        // Save status belongs to WriterDocument. A recovery failure cannot turn
        // a completed ordinary file save into an unsaved-file claim.
        let previous = metadataHandoff
        metadataHandoff = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            await self.waitForHandoff()
            do {
                _ = try await self.coordinator?.acknowledgeSavedFile(saved)
                try await self.library.recordSave(saved, parent: parent)
            }
            catch { self.fail(error) }
        }
    }

    private func waitForHandoff() async {
        while let pendingHandoff = handoff { await pendingHandoff.value }
    }

    func stop() { generation = UUID(); monitor?.cancel(); handoff?.cancel() }
    deinit { monitor?.cancel(); handoff?.cancel() }

    private func fail(_ error: Error) {
        hasFailure = true
        if let keyError = error as? RecoveryKeyError {
            switch keyError {
            case .missing: message = "Recovery key is missing. Existing recovery was preserved. Save a source file."
            case .denied(let reason), .locked(let reason), .unavailable(let reason): message = reason
            }
        } else {
            message = "Recovery is unavailable. Your text is still editable; save it to a file."
        }
        didChange?()
    }
}

/// A lifecycle request stops waiting after five seconds. Cancellation does not
/// roll back a store commit already in progress and never reports it as durable.
@MainActor
private final class RecoveryDeadlineState {
    var worker: Task<Void, Never>?
    var timer: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }

    func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        worker?.cancel(); timer?.cancel(); worker = nil; timer = nil
        continuation.resume(with: result)
    }
}

@MainActor
enum RecoveryDeadline {
    static func run(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let request = RecoveryDeadlineState(continuation)
            request.worker = Task {
                do { try await operation(); request.finish(.success(())) }
                catch { request.finish(.failure(error)) }
            }
            request.timer = Task {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                request.finish(.failure(RecoveryKeyError.unavailable("Recovery did not finish in time. Keep this document open or save it to a file.")))
            }
        }
    }
}
