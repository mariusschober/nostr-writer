import Foundation
import WriterFoundation
import XCTest
@testable import WriterStorage

@MainActor
final class DocumentCatalogTests: XCTestCase {
    func testOptionalFolderMetadataReadsOlderRecordsAndRejectsSourceHistory() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let store = try makeStore(workspace)
        var record = DocumentCatalogRecord(documentID: DocumentID(), title: "Folder", location: workspace.root.absoluteString, bookmark: Data([1]))
        let oldBytes = try JSONEncoder().encode(record)
        XCTAssertNil(try JSONDecoder().decode(DocumentCatalogRecord.self, from: oldBytes).isFolder)
        record.isFolder = true
        try await store.saveCatalogRecord(record)
        let restored = try await store.catalogRecord(for: record.documentID)
        XCTAssertEqual(restored?.isFolder, true)
        record.savedRevision = 0; record.savedDigest = Data(repeating: 1, count: 32)
        do { try await store.saveCatalogRecord(record); XCTFail("Folder accepted document history") } catch { }
        try await store.close()
    }
    func testLocationIdentityAndDerivationSurviveReopenWithoutIndexingBody() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let store = try makeStore(workspace)
        let original = try makeSnapshot(DocumentID(), 7, "SYNTHETIC-PRIVATE-BODY-7fd912")
        _ = try await store.persist(batch(original))
        var record = DocumentCatalogRecord(documentID: original.documentID, title: "Example.md",
            location: workspace.url("Example.md").absoluteString, bookmark: Data([1, 2, 3]))
        record.savedRevision = 7; record.savedDigest = original.digest
        try await store.saveCatalogRecord(record)
        let copy = try makeSnapshot(DocumentID(), 0, original.utf8)
        _ = try await store.persist(batch(copy))
        try await store.saveCatalogRecord(DocumentCatalogRecord(documentID: copy.documentID, parent: original))
        try await store.close()
        let reopened = try makeStore(workspace)
        let restored = try await reopened.catalogRecord(at: record.location!)
        XCTAssertEqual(restored, record)
        let records = try await reopened.catalogRecords()
        XCTAssertEqual(records.first(where: { $0.id == copy.documentID.rawValue })?.parentID, original.documentID.rawValue)
        let raw = try RawDatabase(path: workspace.databaseURL.path)
        XCTAssertEqual(try raw.integer("SELECT COUNT(*) FROM document_catalog"), 2)
        XCTAssertNil(try Data(contentsOf: workspace.databaseURL).range(of: original.utf8))
        try await reopened.close()
    }

    func testDuplicateLocationAndMalformedMetadataDoNotReplaceExistingRecord() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let store = try makeStore(workspace)
        let location = workspace.url("shared.md").absoluteString
        let original = DocumentCatalogRecord(documentID: DocumentID(), title: "Keep", location: location)
        try await store.saveCatalogRecord(original)
        do { try await store.saveCatalogRecord(DocumentCatalogRecord(documentID: DocumentID(), location: location)); XCTFail("Location identity replaced") } catch {}
        var malformed = original; malformed.savedDigest = Data(repeating: 0, count: 32)
        do { try await store.saveCatalogRecord(malformed); XCTFail("Incomplete saved identity accepted") } catch {}
        let preserved = try await store.catalogRecord(at: location)
        XCTAssertEqual(preserved, original)
        try await store.hideCatalogRecord(original.documentID)
        let hidden = try await store.catalogRecord(for: original.documentID)
        XCTAssertEqual(hidden?.isVisible, false)
        XCTAssertEqual(hidden?.location, location)
        try await store.close()
    }

    func testVersionOneRecoveryMigratesWithVerifiedBackup() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let source = try makeSnapshot(DocumentID(), 4, "preserved migration fixture")
        let initial = try makeStore(workspace)
        _ = try await initial.persist(batch(source)); try await initial.close()
        // Version 2 only adds document_catalog; this recreates the exact version
        // 1 schema around an authentic encrypted recovery fixture.
        let connection = try SQLiteConnection(path: workspace.databaseURL.path, busyTimeoutMilliseconds: 1000)
        try connection.execute("DROP TABLE document_catalog")
        try connection.setUserVersion(1); try connection.checkpointAndClose()
        let migrated = try makeStore(workspace)
        guard case .complete(let recovered) = try await migrated.recover(source.documentID) else { return XCTFail("Recovery lost during migration") }
        XCTAssertEqual(recovered.source, source)
        let records = try await migrated.catalogRecords(); XCTAssertTrue(records.isEmpty)
        let backups = backupFiles(in: workspace.root)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try SQLiteConnection.readUserVersion(at: XCTUnwrap(backups.first).path), 1)
        try await migrated.close()
    }
}
