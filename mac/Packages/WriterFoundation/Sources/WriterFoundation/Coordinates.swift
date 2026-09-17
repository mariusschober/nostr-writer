import Foundation

/// Coordinate space a text offset belongs to.
public enum CoordinateEncoding: String, Hashable, Sendable {
    /// UTF-8 byte offset, the protocol coordinate space.
    case utf8
    /// UTF-16 code-unit offset, the AppKit `NSRange` coordinate space.
    case utf16
}

/// Typed failures from coordinate conversion and range construction.
public enum CoordinateError: Error, Equatable, Sendable {
    /// A bound was negative.
    case negativeBound(Int)
    /// An end bound preceded its start bound.
    case invertedRange(lower: Int, upper: Int)
    /// A bound fell outside the text. `limit` is the total length in the relevant encoding.
    case outOfBounds(limit: Int, requested: Int)
    /// `location + length` would exceed `Int.max`, so no end offset exists.
    case rangeOverflow(location: Int, length: Int)
    /// The offset falls inside a Unicode scalar or surrogate pair, so no exact
    /// half-open interval in the other encoding exists.
    case notScalarAligned(offset: Int, encoding: CoordinateEncoding)
}

extension CoordinateError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .negativeBound(let value):
            return "Negative text offset \(value)."
        case .invertedRange(let lower, let upper):
            return "Text range end \(upper) precedes its start \(lower)."
        case .outOfBounds(let limit, let requested):
            return "Text offset \(requested) lies outside 0...\(limit)."
        case .rangeOverflow(let location, let length):
            return "Text range at \(location) of length \(length) overflows the offset space."
        case .notScalarAligned(let offset, let encoding):
            let name = encoding == .utf8 ? "UTF-8" : "UTF-16"
            return "\(name) offset \(offset) does not fall on a Unicode scalar boundary."
        }
    }
}

/// Half-open range in UTF-8 bytes, the frozen HWP coordinate space.
///
/// The interval is `[lowerBound, upperBound)`. Construction checks that the
/// interval is well formed in isolation; whether both bounds land on scalar
/// boundaries is only decidable against a specific `SourceSnapshot`, so that
/// check happens in `SourceSnapshot.byteRange(for:)` and
/// `SourceSnapshot.nativeRange(for:)`.
public struct ByteRange: Hashable, Sendable {

    /// Inclusive start offset, in UTF-8 bytes.
    public let lowerBound: Int
    /// Exclusive end offset, in UTF-8 bytes.
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) throws {
        guard lowerBound >= 0, upperBound >= 0 else {
            throw CoordinateError.negativeBound(min(lowerBound, upperBound))
        }
        guard lowerBound <= upperBound else {
            throw CoordinateError.invertedRange(lower: lowerBound, upper: upperBound)
        }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    /// Number of bytes covered by the interval.
    public var count: Int { upperBound - lowerBound }

    /// Whether the interval is empty.
    public var isEmpty: Bool { lowerBound == upperBound }
}

/// UTF-16 range in the AppKit `NSRange` coordinate space.
///
/// Stored as `location`/`length` so it converts directly to `NSRange`. Offsets
/// that split a surrogate pair are rejected by the snapshot conversions, not here.
public struct NativeRange: Hashable, Sendable {

    /// Inclusive start offset, in UTF-16 code units.
    public let location: Int
    /// Number of UTF-16 code units covered.
    public let length: Int

    public init(location: Int, length: Int) throws {
        guard location >= 0, length >= 0 else {
            throw CoordinateError.negativeBound(min(location, length))
        }
        guard location.addingReportingOverflow(length).overflow == false else {
            throw CoordinateError.rangeOverflow(location: location, length: length)
        }
        self.location = location
        self.length = length
    }

    /// Inclusive start offset, in UTF-16 code units.
    public var lowerBound: Int { location }

    /// Exclusive end offset, in UTF-16 code units.
    public var upperBound: Int { location + length }

    /// Number of UTF-16 code units covered.
    public var count: Int { length }

    /// Whether the range is empty.
    public var isEmpty: Bool { length == 0 }
}
