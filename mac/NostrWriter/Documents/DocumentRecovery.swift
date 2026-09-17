import AppKit
import Security
import WriterFoundation
import WriterStorage

/// Application-owned, injected private-store factory. File and key operations
/// stay on this actor; document windows never wait synchronously for it.
actor RecoveryLibrary {
    private var opening: Task<DocumentStore, Error>?

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
        observe(source)
        await handoff?.value
        guard let coordinator else { throw RecoveryKeyError.unavailable(message) }
        do { _ = try await coordinator.flush(source, atBoundary: boundary) }
        catch { fail(error); throw error }
    }

    func acknowledgeSave(_ saved: SavedFileRevision) {
        // Save status belongs to WriterDocument. A recovery failure cannot turn
        // a completed ordinary file save into an unsaved-file claim.
        Task { [weak self] in
            guard let self else { return }
            await self.handoff?.value
            do { _ = try await self.coordinator?.acknowledgeSavedFile(saved) }
            catch { self.fail(error) }
        }
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
