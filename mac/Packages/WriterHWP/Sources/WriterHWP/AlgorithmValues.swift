import Foundation

/// Exact Unicode text identity. Swift String's canonical-equivalence equality
/// must never collapse distinct record IDs, tokens, roots, or source substrings.
public struct AlgorithmText: Hashable, Comparable, Sendable {
    public let utf8: Data
    public init(_ string: String) { self.utf8 = Data(string.utf8) }
    public init(utf8: Data) throws {
        guard String(data: utf8, encoding: .utf8) != nil else { throw HWPReject("TEXT_DOMAIN") }
        self.utf8 = Data(utf8)
    }
    public init(scalars: [UInt32]) throws {
        var value = String.UnicodeScalarView()
        for scalar in scalars {
            guard let s = Unicode.Scalar(scalar) else { throw HWPReject("TEXT_DOMAIN") }
            value.append(s)
        }
        self.init(String(value))
    }
    public var string: String { String(decoding: utf8, as: UTF8.self) }
    public var scalars: [UInt32] { string.unicodeScalars.map(\.value) }
    public var count: Int { string.unicodeScalars.count }
    public var isEmpty: Bool { utf8.isEmpty }
    public static func < (a: Self, b: Self) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }
    public var value: HWPValue { .text(utf8) }
}

public enum HWPAlgorithmValues {
    public static let maximumInteger: Int64 = 9_007_199_254_740_991
    public static func need(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw HWPReject(reason) }
    }
    public static func integer(_ value: HWPValue?, low: Int64 = 0,
                               high: Int64 = maximumInteger) throws -> Int64 {
        let result: Int64
        switch value {
        case .unsigned(let number) where number <= UInt64(Int64.max): result = Int64(number)
        case .negative(let number) where number < 0: result = number
        default: throw HWPReject("INTEGER_DOMAIN")
        }
        guard low <= result, result <= high else { throw HWPReject("INTEGER_DOMAIN") }
        return result
    }
    public static func text(_ value: HWPValue?, maximum: Int = 200_000) throws -> AlgorithmText {
        guard case .text(let bytes) = value else { throw HWPReject("TEXT_DOMAIN") }
        // One valid scalar has at most four UTF-8 bytes. Check before decoding.
        guard maximum >= 0, maximum <= Int.max / 4, bytes.count <= maximum * 4 else { throw HWPReject("TEXT_DOMAIN") }
        let text = try AlgorithmText(utf8: bytes)
        guard text.count <= maximum else { throw HWPReject("TEXT_DOMAIN") }
        return text
    }
    public static func array(_ value: HWPValue?, reason: String = "MALFORMED_INPUT") throws -> [HWPValue] {
        guard case .array(let items) = value else { throw HWPReject(reason) }
        return items
    }
    public static func object(_ value: HWPValue?, reason: String = "OBJECT_FIELDS") throws -> [AlgorithmText: HWPValue] {
        guard case .map(let entries) = value else { throw HWPReject(reason) }
        var result: [AlgorithmText: HWPValue] = [:]
        for entry in entries {
            guard case .text(let bytes) = entry.key else { throw HWPReject(reason) }
            let key = try AlgorithmText(utf8: bytes)
            guard result.updateValue(entry.value, forKey: key) == nil else { throw HWPReject(reason) }
        }
        return result
    }
    public static func shape(_ value: HWPValue?, required: Set<String>, optional: Set<String> = []) throws {
        let fields = try Set(object(value).keys)
        let required = Set(required.map(AlgorithmText.init)), allowed = Set(optional.map(AlgorithmText.init))
        guard required.isSubset(of: fields), fields.isSubset(of: required.union(allowed)) else { throw HWPReject("OBJECT_FIELDS") }
    }
}
