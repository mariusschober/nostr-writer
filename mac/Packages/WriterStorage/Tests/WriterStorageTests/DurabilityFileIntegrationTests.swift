import XCTest
import Foundation
import WriterFoundation
@testable import WriterStorage

/// Composes the actual encrypted store, scheduler and coordinated source files.
/// This is local component evidence, not NSDocument/UI/provider acceptance.
@MainActor
final class DurabilityFileIntegrationTests: XCTestCase {
    func testCloseFlushesNewestExactSourceAcrossEncryptedStoreReopen() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let config = DocumentStoreConfiguration(databaseURL: workspace.databaseURL, retentionPolicy: .rollingJournal)
        let key = InMemoryKeyProvider(key: testKey()), store = try DocumentStore(configuration: config, keyProvider: key)
        let id = DocumentID(), coordinator = try RecoveryCoordinator(documentID: id, persistence: store)
        let initial = try makeSnapshot(id, 0, Data([0xef,0xbb,0xbf])+Data("synthetic recovery\r\ne\u{301}\n".utf8))
        _ = try await coordinator.flush(initial, atBoundary: .save)
        let files = CoordinatedSourceFiles(), url = workspace.url("source.md")
        let saved = try await files.create(initial, at: url)
        _ = try await coordinator.acknowledgeSavedFile(saved.saved)
        let next = try makeSnapshot(id, 1, initial.utf8+Data("unsaved after file snapshot".utf8))
        try await coordinator.observe(next)
        // Close must force the pending checkpoint instead of cancelling its timer
        // and incorrectly abandoning the only copy of the newest revision.
        _ = try await coordinator.close()
        let state = await coordinator.state()
        XCTAssertTrue(state.isClosed); XCTAssertFalse(state.isClosing)
        XCTAssertTrue(state.isDurablyRecovered); XCTAssertFalse(state.isSaved)
        try await store.close()
        let reopened = try DocumentStore(configuration: config, keyProvider: key)
        guard case .complete(let recovered) = try await reopened.recover(id) else { return XCTFail("Latest source was not recoverable") }
        XCTAssertEqual(recovered.source, next)
        XCTAssertEqual(try Data(contentsOf: url), initial.utf8)
        XCTAssertTrue(filesContaining(next.utf8, in: storeFiles(workspace.databaseURL)).isEmpty)
        try await reopened.close()
    }

    func testUnavailableRecoveryKeyDoesNotPreventOrdinarySourceSaveOrClaimRecovery() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let key = testKey(), provider = InMemoryKeyProvider(key: key)
        let store = try makeStore(workspace, provider: provider)
        let id = DocumentID(), coordinator = try RecoveryCoordinator(documentID: id, persistence: store), files = CoordinatedSourceFiles()
        let initial = try makeSnapshot(id, 0, "original synthetic text")
        _ = try await coordinator.flush(initial, atBoundary: .save)
        let url = workspace.url("source.md"), saved = try await files.create(initial, at: url)
        _ = try await coordinator.acknowledgeSavedFile(saved.saved)
        provider.useFailure(.locked("Locked for this synthetic test."))
        let next = try makeSnapshot(id, 1, "new synthetic text\r\n🇪🇸")
        do { _ = try await coordinator.flush(next, atBoundary: .save); XCTFail("Unavailable key was accepted") }
        catch { XCTAssertNotNil(error as? RecoveryCoordinatorError) }
        let ordinary = try await files.replace(next, at: url, expecting: saved.localVersion)
        _ = try await coordinator.acknowledgeSavedFile(ordinary.saved)
        let partial = await coordinator.state()
        XCTAssertTrue(partial.isSaved); XCTAssertFalse(partial.isDurablyRecovered); XCTAssertNotNil(partial.lastFailure)
        XCTAssertEqual(try Data(contentsOf: url), next.utf8)
        provider.useKey(key); await coordinator.retry(); await coordinator.awaitQuiescence()
        let complete = await coordinator.state(); XCTAssertTrue(complete.isSaved); XCTAssertTrue(complete.isDurablyRecovered)
        _ = try await coordinator.close(); try await store.close()
    }
}
