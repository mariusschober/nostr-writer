import Foundation
import WriterFoundation

/// App-private metadata only. Source bodies remain in encrypted recovery chunks.
/// A filename/bookmark can reveal location or activity; this is not anonymity.
public struct DocumentCatalogRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var location: String?
    public var bookmark: Data?
    public var title: String
    public var savedRevision: UInt64?
    public var savedDigest: Data?
    public var parentID: UUID?
    public var parentRevision: UInt64?
    public var parentDigest: Data?
    public var isOpen: Bool
    public var isVisible: Bool
    public var updatedAt: Double
    // Additive optional metadata keeps existing schema-2 records readable.
    public var isFolder: Bool?
    public var isPinned: Bool?
    public var textImport: TextImportReceipt?
    public var managedAssets: [ManagedAsset]?
    public var assetFolderBookmark: Data?
    public var documentID: DocumentID { DocumentID(rawValue: id) }

    public init(documentID: DocumentID, title: String = "Untitled", location: String? = nil,
                bookmark: Data? = nil, parent: SourceSnapshot? = nil) {
        id = documentID.rawValue; self.title = title; self.location = location; self.bookmark = bookmark
        parentID = parent?.documentID.rawValue; parentRevision = parent?.revision.rawValue; parentDigest = parent?.digest
        isOpen = true; isVisible = true; updatedAt = Date().timeIntervalSince1970
    }

    func validate() throws {
        try textImport?.validate()
        try ManagedAsset.validateSet(managedAssets ?? [])
        guard (assetFolderBookmark?.count ?? 0) <= ScopedSourceFiles.maximumBookmarkBytes,
              managedAssets?.isEmpty != false || assetFolderBookmark != nil else { throw SourceAccessError.invalidBookmark }
        guard title.utf8.count <= 4096, (bookmark?.count ?? 0) <= ScopedSourceFiles.maximumBookmarkBytes,
              (location?.utf8.count ?? 0) <= 8192, updatedAt.isFinite,
              savedDigest == nil || savedDigest?.count == 32,
              parentDigest == nil || parentDigest?.count == 32,
              (savedRevision == nil) == (savedDigest == nil),
              (parentID == nil) == (parentRevision == nil), (parentID == nil) == (parentDigest == nil),
              parentID != id else {
            throw StorageError.invariantViolation("Document metadata is malformed or exceeds its bounds.")
        }
        if isFolder == true, location == nil || bookmark == nil || savedDigest != nil || parentID != nil || textImport != nil || managedAssets?.isEmpty == false {
            throw StorageError.invariantViolation("A library folder must be a selected location without document history.")
        }
        if let location {
            guard !location.utf8.contains(0), let url = URL(string: location), url.isFileURL,
                  url.host == nil || url.host == "" || url.host == "localhost" else {
                throw StorageError.invariantViolation("The document location is not a local file URL.")
            }
        }
    }
}

extension DocumentStore {
    public func catalogRecords() throws -> [DocumentCatalogRecord] {
        let connection = try catalogConnection()
        let query = try connection.prepare("SELECT document_id, location_key, metadata FROM document_catalog ORDER BY updated_at DESC LIMIT 4097")
        var result: [DocumentCatalogRecord] = []
        var totalBytes = 0
        while try query.step() {
            totalBytes += query.columnByteCount(2)
            guard totalBytes <= 32 * 1024 * 1024 else { throw StorageError.invariantViolation("Document metadata exceeds the library budget.") }
            guard result.count < 4096 else { throw StorageError.invariantViolation("The document library exceeds its entry limit.") }
            result.append(try decodeCatalog(query))
        }
        return result
    }

    public func catalogRecord(for id: DocumentID) throws -> DocumentCatalogRecord? {
        let query = try catalogConnection().prepare("SELECT document_id, location_key, metadata FROM document_catalog WHERE document_id = ?")
        try query.bindText(1, id.rawValue.uuidString)
        return try query.step() ? decodeCatalog(query) : nil
    }

    public func catalogRecord(at location: String) throws -> DocumentCatalogRecord? {
        guard location.utf8.count <= 8192 else { throw StorageError.invariantViolation("The document location exceeds its bound.") }
        let query = try catalogConnection().prepare("SELECT document_id, location_key, metadata FROM document_catalog WHERE location_key = ?")
        try query.bindText(1, location)
        return try query.step() ? decodeCatalog(query) : nil
    }

    /// Catalog updates cannot replace an identity already associated with the
    /// same location. A Save As creates another identity at another location.
    public func saveCatalogRecord(_ record: DocumentCatalogRecord) throws {
        try record.validate()
        let connection = try catalogConnection()
        let bytes = try JSONEncoder().encode(record)
        try connection.withTransaction {
            let size = try connection.prepare("SELECT COALESCE(SUM(length(metadata)), 0) FROM document_catalog WHERE document_id != ?")
            try size.bindText(1, record.id.uuidString)
            guard try size.step(), size.columnInt64(0) <= 32 * 1024 * 1024 - Int64(bytes.count) else {
                throw StorageError.invariantViolation("Document metadata has reached the library budget.")
            }
            if try catalogRecord(for: record.documentID) == nil {
                let count = try connection.prepare("SELECT COUNT(*) FROM document_catalog")
                guard try count.step(), count.columnInt64(0) < 4096 else {
                    throw StorageError.invariantViolation("The document library has reached its entry limit.")
                }
            }
            let query = try connection.prepare("""
                INSERT INTO document_catalog(document_id, location_key, metadata, updated_at) VALUES(?, ?, ?, ?)
                ON CONFLICT(document_id) DO UPDATE SET location_key=excluded.location_key, metadata=excluded.metadata, updated_at=excluded.updated_at
                """)
            try query.bindText(1, record.id.uuidString)
            if let location = record.location { try query.bindText(2, location) }
            // Unbound parameters are SQL NULL, so unsaved entries do not collide.
            try query.bindBlob(3, bytes); try query.bindDouble(4, record.updatedAt)
            try query.step()
        }
    }

    /// Forgetting a recent reference never deletes the source or recovery.
    public func hideCatalogRecord(_ id: DocumentID) throws {
        guard var record = try catalogRecord(for: id) else { return }
        record.isVisible = false; record.updatedAt = Date().timeIntervalSince1970
        try saveCatalogRecord(record)
    }

    private func decodeCatalog(_ query: SQLiteStatement) throws -> DocumentCatalogRecord {
        guard query.columnByteCount(2) <= 1_500_000,
              let record = try? JSONDecoder().decode(DocumentCatalogRecord.self, from: query.requiredBlob(2)),
              record.id.uuidString == query.columnText(0), record.location == query.columnText(1) else {
            throw StorageError.corruptDatabase("The document catalog record is malformed or inconsistent.")
        }
        try record.validate()
        return record
    }
}
