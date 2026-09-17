import Foundation

/// Stable document identity, independent of file path, title or any name.
///
/// Identity is assigned once per document and survives rename/move. Byte-identical
/// files are not automatically the same document; see `DATA.md`.
public struct DocumentID: Hashable, Sendable, CustomStringConvertible {

    /// Raw UUID backing this identity.
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Fresh identity drawn from the system random source.
    public init() {
        self.rawValue = UUID()
    }

    public var description: String { rawValue.uuidString }
}

/// Monotonic revision counter scoped to one document session.
///
/// `Revision` is session ordering metadata, never content identity. Content
/// identity is byte equality plus the SHA-256 digest in `SourceSnapshot`.
public struct Revision: Hashable, Comparable, Sendable, CustomStringConvertible {

    /// Raw monotonically increasing counter value.
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Revision, rhs: Revision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The following revision, or `nil` when the counter would overflow.
    public var next: Revision? {
        let (value, overflow) = rawValue.addingReportingOverflow(1)
        return overflow ? nil : Revision(value)
    }

    public var description: String { String(rawValue) }
}
