import Foundation
import CryptoKit

/// Typed failures from exact-source snapshot construction.
public enum SourceSnapshotError: Error, Equatable, Sendable {
    /// The supplied bytes are not well-formed UTF-8. `byteOffset` is the index of
    /// the first byte that cannot begin or continue a valid scalar.
    case invalidUTF8(byteOffset: Int)
}

extension SourceSnapshotError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidUTF8(let byteOffset):
            return "Source bytes are not valid UTF-8 (first invalid byte at offset \(byteOffset))."
        }
    }
}

/// An immutable, exactly identified revision of one document's source bytes.
///
/// The snapshot stores the bytes as supplied. It never re-encodes, trims,
/// line-ending-normalises or Unicode-normalises them, so two spellings of the
/// same visible text stay distinct values with distinct digests. Content
/// identity is `utf8` byte equality and `digest`; Swift's canonically
/// equivalent `String ==` is deliberately not used anywhere in this type.
public struct SourceSnapshot: Hashable, Sendable {

    /// Stable document identity this revision belongs to.
    public let documentID: DocumentID

    /// Monotonic revision of the source within the document session.
    public let revision: Revision

    /// Exact UTF-8 source bytes as supplied.
    public let utf8: Data

    /// SHA-256 over `utf8`. Always exactly 32 bytes.
    public let digest: Data

    /// Creates a snapshot after strict UTF-8 validation and digest computation.
    ///
    /// Throws ``SourceSnapshotError/invalidUTF8(byteOffset:)`` if the bytes are
    /// not well-formed UTF-8. Overlong encodings, surrogate code points and
    /// scalars above U+10FFFF are rejected; noncharacters and unassigned code
    /// points are accepted unchanged, as UTF-8 permits.
    public init(documentID: DocumentID, revision: Revision, utf8: Data) throws {
        if let invalidOffset = SourceSnapshot.firstInvalidUTF8Offset(in: utf8) {
            throw SourceSnapshotError.invalidUTF8(byteOffset: invalidOffset)
        }
        self.documentID = documentID
        self.revision = revision
        // Data slices may retain a nonzero startIndex; protocol offsets start at zero.
        self.utf8 = Data(utf8)
        self.digest = SourceSnapshot.sha256(utf8)
    }

    // MARK: - Digests

    /// SHA-256 of `data`, as 32 raw bytes.
    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    /// Lowercase hexadecimal rendering of `digest`.
    public var digestHex: String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Byte facts

    /// Exact number of source bytes.
    public var byteCount: Int { utf8.count }

    /// Number of UTF-8 bytes. Same as `byteCount`; named for protocol parity.
    public var utf8Count: Int { utf8.count }

    /// Number of Unicode scalars in the source.
    public var scalarCount: Int { string.unicodeScalars.count }

    /// Number of UTF-16 code units in the source.
    public var utf16Count: Int {
        var total = 0
        for scalar in string.unicodeScalars {
            total += SourceSnapshot.utf16Length(of: scalar)
        }
        return total
    }

    /// The source text decoded from the exact stored bytes.
    ///
    /// Decoding is total because `utf8` was validated at construction. Do not use
    /// Swift string comparison for integrity; compare `utf8` or `digest`.
    public var string: String {
        String(decoding: utf8, as: UTF8.self)
    }

    // MARK: - Identity

    /// Byte-for-byte equality with another snapshot, ignoring identity metadata.
    public func hasIdenticalBytes(to other: SourceSnapshot) -> Bool {
        utf8 == other.utf8
    }

    // MARK: - Coordinate conversion

    /// Converts a half-open UTF-8 byte interval to the equivalent UTF-16 range.
    ///
    /// Both bounds must land on Unicode scalar boundaries. A bound inside a
    /// multibyte scalar is rejected rather than rounded, because a rounded
    /// selection would silently cover different bytes than the caller asked for.
    public func nativeRange(for byteRange: ByteRange) throws -> NativeRange {
        guard byteRange.upperBound <= utf8.count else {
            throw CoordinateError.outOfBounds(limit: utf8.count, requested: byteRange.upperBound)
        }
        guard let lower = utf16Offset(atUTF8Boundary: byteRange.lowerBound) else {
            throw CoordinateError.notScalarAligned(offset: byteRange.lowerBound, encoding: .utf8)
        }
        guard let upper = utf16Offset(atUTF8Boundary: byteRange.upperBound) else {
            throw CoordinateError.notScalarAligned(offset: byteRange.upperBound, encoding: .utf8)
        }
        return try NativeRange(location: lower, length: upper - lower)
    }

    /// Converts a UTF-16 range to the equivalent half-open UTF-8 byte interval.
    ///
    /// A range that starts or ends inside a surrogate pair is rejected, since no
    /// half-open byte interval corresponds to half a scalar.
    public func byteRange(for nativeRange: NativeRange) throws -> ByteRange {
        let limit = utf16Count
        guard nativeRange.upperBound <= limit else {
            throw CoordinateError.outOfBounds(limit: limit, requested: nativeRange.upperBound)
        }
        guard let lower = utf8Offset(atUTF16Boundary: nativeRange.lowerBound) else {
            throw CoordinateError.notScalarAligned(offset: nativeRange.lowerBound, encoding: .utf16)
        }
        guard let upper = utf8Offset(atUTF16Boundary: nativeRange.upperBound) else {
            throw CoordinateError.notScalarAligned(offset: nativeRange.upperBound, encoding: .utf16)
        }
        return try ByteRange(lowerBound: lower, upperBound: upper)
    }

    // MARK: - UTF-8 validation

    /// First byte offset that is not part of well-formed UTF-8, or `nil` when valid.
    ///
    /// This is a strict RFC 3629 check: overlong encodings, surrogate code
    /// points and scalars above U+10FFFF are rejected. The validator only
    /// inspects encodings; it never normalises or rewrites content.
    public static func firstInvalidUTF8Offset(in data: Data) -> Int? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { raw -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            var index = 0

            func isContinuation(_ byte: UInt8) -> Bool {
                byte >= 0x80 && byte <= 0xBF
            }

            while index < count {
                let lead = bytes[index]
                if lead < 0x80 {
                    index += 1
                    continue
                }
                switch lead {
                case 0xC2...0xDF:
                    guard index + 1 < count, isContinuation(bytes[index + 1]) else { return index }
                    index += 2
                case 0xE0:
                    guard index + 2 < count,
                          bytes[index + 1] >= 0xA0, bytes[index + 1] <= 0xBF,
                          isContinuation(bytes[index + 2]) else { return index }
                    index += 3
                case 0xE1...0xEC, 0xEE...0xEF:
                    guard index + 2 < count,
                          isContinuation(bytes[index + 1]),
                          isContinuation(bytes[index + 2]) else { return index }
                    index += 3
                case 0xED:
                    // Excludes the surrogate range U+D800...U+DFFF.
                    guard index + 2 < count,
                          bytes[index + 1] >= 0x80, bytes[index + 1] <= 0x9F,
                          isContinuation(bytes[index + 2]) else { return index }
                    index += 3
                case 0xF0:
                    guard index + 3 < count,
                          bytes[index + 1] >= 0x90, bytes[index + 1] <= 0xBF,
                          isContinuation(bytes[index + 2]),
                          isContinuation(bytes[index + 3]) else { return index }
                    index += 4
                case 0xF1...0xF3:
                    guard index + 3 < count,
                          isContinuation(bytes[index + 1]),
                          isContinuation(bytes[index + 2]),
                          isContinuation(bytes[index + 3]) else { return index }
                    index += 4
                case 0xF4:
                    guard index + 3 < count,
                          bytes[index + 1] >= 0x80, bytes[index + 1] <= 0x8F,
                          isContinuation(bytes[index + 2]),
                          isContinuation(bytes[index + 3]) else { return index }
                    index += 4
                default:
                    // 0x80...0xC1 are stray continuations or overlong leads;
                    // 0xF5...0xFF exceed the Unicode range.
                    return index
                }
            }
            return nil
        }
    }

    // MARK: - Scalar arithmetic

    /// UTF-8 encoding length of a scalar, in bytes.
    static func utf8Length(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value <= 0x7F { return 1 }
        if value <= 0x7FF { return 2 }
        if value <= 0xFFFF { return 3 }
        return 4
    }

    /// UTF-16 encoding length of a scalar, in code units.
    static func utf16Length(of scalar: Unicode.Scalar) -> Int {
        scalar.value > 0xFFFF ? 2 : 1
    }

    // MARK: - Private boundary lookup

    /// UTF-16 offset for an exact UTF-8 scalar boundary, or `nil` if unaligned.
    private func utf16Offset(atUTF8Boundary target: Int) -> Int? {
        if target == 0 { return 0 }
        var utf8Offset = 0
        var utf16Offset = 0
        for scalar in string.unicodeScalars {
            utf8Offset += SourceSnapshot.utf8Length(of: scalar)
            utf16Offset += SourceSnapshot.utf16Length(of: scalar)
            if utf8Offset == target { return utf16Offset }
            if utf8Offset > target { return nil }
        }
        return nil
    }

    /// UTF-8 offset for an exact UTF-16 scalar boundary, or `nil` if unaligned.
    private func utf8Offset(atUTF16Boundary target: Int) -> Int? {
        if target == 0 { return 0 }
        var utf8Offset = 0
        var utf16Offset = 0
        for scalar in string.unicodeScalars {
            utf8Offset += SourceSnapshot.utf8Length(of: scalar)
            utf16Offset += SourceSnapshot.utf16Length(of: scalar)
            if utf16Offset == target { return utf8Offset }
            if utf16Offset > target { return nil }
        }
        return nil
    }
}
