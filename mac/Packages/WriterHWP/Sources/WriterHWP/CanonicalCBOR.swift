import Foundation
import WriterFoundation

/// The restricted deterministic domain in frozen hwp0/core.py. Text equality
/// remains byte equality: Swift String's canonical equivalence is not wire identity.
public indirect enum HWPValue: Equatable, Sendable {
    case unsigned(UInt64), negative(Int64), bytes(Data), text(Data)
    case array([HWPValue]), map([HWPEntry]), tag18(HWPValue)
    case boolean(Bool), null

    public static func text(_ string: String) -> HWPValue { .text(Data(string.utf8)) }
    public static func integer(_ value: Int64) -> HWPValue {
        value >= 0 ? .unsigned(UInt64(value)) : .negative(value)
    }

    private enum MapKey: Hashable {
        case unsigned(UInt64), negative(Int64), text(Data)
        init?(_ value: HWPValue) {
            switch value {
            case .unsigned(let number): self = .unsigned(number)
            case .negative(let number): self = .negative(number)
            case .text(let bytes): self = .text(bytes)
            default: return nil
            }
        }
    }
    private static func dictionary(_ entries: [HWPEntry]) -> [MapKey: HWPValue]? {
        var result: [MapKey: HWPValue] = [:]
        for entry in entries {
            guard let key = MapKey(entry.key), result[key] == nil else { return nil }
            result[key] = entry.value
        }
        return result
    }
    public static func == (left: HWPValue, right: HWPValue) -> Bool {
        switch (left, right) {
        case (.unsigned(let a), .unsigned(let b)): a == b
        case (.negative(let a), .negative(let b)): a == b
        case (.bytes(let a), .bytes(let b)), (.text(let a), .text(let b)): a == b
        case (.boolean(let a), .boolean(let b)): a == b
        case (.null, .null): true
        case (.array(let a), .array(let b)): a == b
        case (.tag18(let a), .tag18(let b)): a == b
        case (.map(let a), .map(let b)):
            // Semantic map equality is order-independent, while text keys remain
            // exact bytes. Encoding separately enforces the canonical key order.
            if a.count != b.count { false }
            else if let aa = dictionary(a), let bb = dictionary(b) { aa == bb }
            else { a == b } // Invalid domains still have reflexive value equality.
        default: false
        }
    }
}

public struct HWPEntry: Equatable, Sendable {
    public let key: HWPValue
    public let value: HWPValue
    public init(_ key: HWPValue, _ value: HWPValue) { self.key = key; self.value = value }
}

public struct HWPReject: Error, Equatable, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

public enum HWPCBOR {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumItems = 100_000
    public static let maximumDepth = 32

    public static func encode(_ value: HWPValue) throws -> Data {
        var output = Data()
        try append(value, depth: 0, to: &output)
        return output
    }

    public static func decode(_ raw: Data) throws -> HWPValue {
        guard raw.count <= maximumBytes else { throw HWPReject("byte-string-domain") }
        var parser = Parser(bytes: Data(raw))
        let value = try parser.parse(depth: 0)
        guard parser.offset == raw.count else { throw HWPReject("cbor-trailing-data") }
        guard try encode(value) == raw else { throw HWPReject("cbor-nondeterministic") }
        return value
    }

    private static func head(_ major: UInt8, _ value: UInt64) -> Data {
        if value < 24 { return Data([(major << 5) | UInt8(value)]) }
        let width: Int
        let code: UInt8
        if value <= 0xff { width = 1; code = 24 }
        else if value <= 0xffff { width = 2; code = 25 }
        else if value <= 0xffff_ffff { width = 4; code = 26 }
        else { width = 8; code = 27 }
        var result = Data([(major << 5) | code])
        for index in (0..<width).reversed() { result.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
        return result
    }

    private static func add(_ data: Data, to output: inout Data) throws {
        guard data.count <= maximumBytes - output.count else { throw HWPReject("byte-string-domain") }
        output.append(data)
    }

    private static func isKey(_ value: HWPValue) -> Bool {
        switch value { case .unsigned, .negative, .text: true; default: false }
    }

    private static func append(_ value: HWPValue, depth: Int, to output: inout Data) throws {
        try Task.checkCancellation()
        guard depth <= maximumDepth else { throw HWPReject("cbor-depth") }
        switch value {
        case .unsigned(let integer): try add(head(0, integer), to: &output)
        case .negative(let integer):
            guard integer < 0 else { throw HWPReject("cbor-integer-domain") }
            try add(head(1, UInt64(-(integer + 1))), to: &output)
        case .bytes(let data):
            guard data.count <= maximumBytes else { throw HWPReject("byte-string-domain") }
            try add(head(2, UInt64(data.count)), to: &output); try add(data, to: &output)
        case .text(let bytes):
            guard bytes.count <= maximumBytes else { throw HWPReject("text-size") }
            guard SourceSnapshot.firstInvalidUTF8Offset(in: bytes) == nil else { throw HWPReject("unicode-scalar") }
            try add(head(3, UInt64(bytes.count)), to: &output); try add(bytes, to: &output)
        case .array(let values):
            guard values.count <= maximumItems else { throw HWPReject("array-size") }
            try add(head(4, UInt64(values.count)), to: &output)
            for item in values { try append(item, depth: depth + 1, to: &output) }
        case .map(let entries):
            guard entries.count <= maximumItems else { throw HWPReject("map-size") }
            var ordered: [(key: Data, value: HWPValue)] = []
            var encodedKeyBytes = 0
            for entry in entries {
                guard isKey(entry.key) else { throw HWPReject("map-key-type") }
                var key = Data(); try append(entry.key, depth: depth + 1, to: &key)
                guard key.count <= maximumBytes - encodedKeyBytes else { throw HWPReject("byte-string-domain") }
                encodedKeyBytes += key.count
                ordered.append((key, entry.value))
            }
            ordered.sort { $0.key.lexicographicallyPrecedes($1.key) }
            try add(head(5, UInt64(entries.count)), to: &output)
            var previous: Data?
            for entry in ordered {
                guard previous != entry.key else { throw HWPReject("cbor-duplicate-key") }
                previous = entry.key
                try add(entry.key, to: &output)
                try append(entry.value, depth: depth + 1, to: &output)
            }
        case .tag18(let value):
            try add(Data([0xd2]), to: &output)
            try append(value, depth: depth + 1, to: &output)
        case .boolean(let value): try add(Data([value ? 0xf5 : 0xf4]), to: &output)
        case .null: try add(Data([0xf6]), to: &output)
        }
    }

    private struct Parser {
        let bytes: Data
        var offset = 0
        var visited = 0

        mutating func take(_ count: UInt64) throws -> Data {
            guard count <= UInt64(bytes.count - offset) else { throw HWPReject("cbor-truncated") }
            let end = offset + Int(count)
            let value = bytes.subdata(in: offset..<end)
            offset = end
            return value
        }

        mutating func parse(depth: Int) throws -> HWPValue {
            try Task.checkCancellation()
            guard depth <= maximumDepth else { throw HWPReject("cbor-depth") }
            visited += 1
            guard visited <= maximumItems else { throw HWPReject("cbor-item-budget") }
            let first = try take(1)[0]
            let major = first >> 5, info = first & 31
            if major == 7 {
                switch info {
                case 20: return .boolean(false)
                case 21: return .boolean(true)
                case 22: return .null
                default: throw HWPReject("cbor-simple-or-float")
                }
            }
            guard info <= 27 else { throw HWPReject("cbor-indefinite-or-reserved") }
            var count = UInt64(info)
            if info >= 24 {
                let width = 1 << (info - 24)
                count = try take(UInt64(width)).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                let minimum: UInt64 = info == 24 ? 24 : (UInt64(1) << (8 * (1 << (info - 25))))
                guard count >= minimum else { throw HWPReject("cbor-nonminimal") }
            }
            switch major {
            case 0: return .unsigned(count)
            case 1:
                guard count < (UInt64(1) << 63) else { throw HWPReject("cbor-integer-domain") }
                return .negative(-1 - Int64(count))
            case 2: return .bytes(try take(count))
            case 3:
                let text = try take(count)
                guard SourceSnapshot.firstInvalidUTF8Offset(in: text) == nil else { throw HWPReject("invalid-utf8") }
                return .text(text)
            case 4:
                guard count <= maximumItems else { throw HWPReject("array-size") }
                guard count <= bytes.count - offset else { throw HWPReject("cbor-truncated") }
                var values: [HWPValue] = []
                values.reserveCapacity(Int(count))
                for _ in 0..<count { values.append(try parse(depth: depth + 1)) }
                return .array(values)
            case 5:
                guard count <= maximumItems else { throw HWPReject("map-size") }
                guard count <= (bytes.count - offset) / 2 else { throw HWPReject("cbor-truncated") }
                var entries: [HWPEntry] = []; var previous: Data?
                entries.reserveCapacity(Int(count))
                for _ in 0..<count {
                    let begin = offset
                    let key = try parse(depth: depth + 1)
                    let rawKey = bytes.subdata(in: begin..<offset)
                    guard isKey(key) else { throw HWPReject("map-key-type") }
                    if let previous, !previous.lexicographicallyPrecedes(rawKey) {
                        throw HWPReject("cbor-key-order-or-duplicate")
                    }
                    previous = rawKey
                    entries.append(HWPEntry(key, try parse(depth: depth + 1)))
                }
                return .map(entries)
            case 6:
                guard count == 18 else { throw HWPReject("unsupported-tag") }
                return .tag18(try parse(depth: depth + 1))
            default: throw HWPReject("unsupported-tag")
            }
        }
    }
}
