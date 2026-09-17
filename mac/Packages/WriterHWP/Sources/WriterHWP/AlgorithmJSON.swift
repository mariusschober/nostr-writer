import Foundation
import BigInt

/// Python json.dumps(sort_keys=True, ensure_ascii=True, separators=(',', ':'))
/// for the joined protocol's integer-only domain. This is a snapshot comparison
/// format inside the frozen algorithm, not a replacement for canonical CBOR.
public enum HWPAlgorithmJSON {
    public static func snapshot(_ value: HWPValue, maximumBytes: Int = 100_000_000) throws -> Data {
        var output = Data()
        func append(_ value: String) throws {
            let bytes = Data(value.utf8)
            guard maximumBytes >= output.count, bytes.count <= maximumBytes - output.count else { throw HWPReject("INPUT_SIZE_LIMIT") }
            output.append(bytes)
        }
        func string(_ bytes: Data) throws {
            let value = try AlgorithmText(utf8: bytes)
            try append("\"")
            for (index, character) in value.string.unicodeScalars.enumerated() {
                if index % 1024 == 0 { try Task.checkCancellation() }
                let scalar = character.value
                switch scalar {
                case 0x22: try append("\\\"")
                case 0x5c: try append("\\\\")
                case 0x08: try append("\\b")
                case 0x0c: try append("\\f")
                case 0x0a: try append("\\n")
                case 0x0d: try append("\\r")
                case 0x09: try append("\\t")
                case 0x20...0x7e: try append(String(Unicode.Scalar(scalar)!))
                case 0...0xffff: try append(String(format: "\\u%04x", scalar))
                default:
                    let offset = scalar - 0x10000
                    try append(String(format: "\\u%04x\\u%04x", 0xd800 + (offset >> 10), 0xdc00 + (offset & 0x3ff)))
                }
            }
            try append("\"")
        }
        func emit(_ value: HWPValue, depth: Int) throws {
            try Task.checkCancellation()
            guard depth <= 32 else { throw HWPReject("MALFORMED_INPUT") }
            switch value {
            case .unsigned(let number): try append(String(number))
            case .negative(let number) where number < 0: try append(String(number))
            case .text(let bytes): try string(bytes)
            case .boolean(let value): try append(value ? "true" : "false")
            case .null: try append("null")
            case .array(let values):
                try append("[")
                for (index, v) in values.enumerated() { if index > 0 { try append(",") }; try emit(v, depth: depth + 1) }
                try append("]")
            case .map(let entries):
                let allText = entries.allSatisfy { if case .text = $0.key { true } else { false } }
                let allInteger = entries.allSatisfy { if case .unsigned = $0.key { true } else if case .negative(let n) = $0.key { n < 0 } else { false } }
                guard allText || allInteger else { throw HWPReject("MALFORMED_INPUT") }
                func number(_ value: HWPValue) -> BigInt { switch value { case .unsigned(let n): BigInt(n); case .negative(let n): BigInt(n); default: 0 } }
                let sorted = entries.sorted {
                    if allInteger { return number($0.key) < number($1.key) }
                    if case .text(let a) = $0.key, case .text(let b) = $1.key { return a.lexicographicallyPrecedes(b) }
                    return false
                }
                try append("{")
                var previous: HWPValue?
                for (index, entry) in sorted.enumerated() {
                    guard previous != entry.key else { throw HWPReject("MALFORMED_INPUT") }; previous = entry.key
                    if index > 0 { try append(",") }
                    if case .text(let bytes) = entry.key { try string(bytes) }
                    else { try string(Data(number(entry.key).description.utf8)) }
                    try append(":"); try emit(entry.value, depth: depth + 1)
                }
                try append("}")
            default: throw HWPReject("MALFORMED_INPUT")
            }
        }
        try emit(value, depth: 0)
        return output
    }

    /// json.loads(snapshot(value)) converts integer map keys into decimal text.
    /// Call only after snapshot validated the bounded input domain.
    static func normalized(_ value: HWPValue) throws -> HWPValue {
        try Task.checkCancellation()
        switch value {
        case .array(let values): return .array(try values.map(normalized))
        case .map(let entries):
            return .map(try entries.map { entry in
                try Task.checkCancellation()
                let key: HWPValue
                switch entry.key {
                case .unsigned(let n): key = .text(String(n))
                case .negative(let n): key = .text(String(n))
                default: key = entry.key
                }
                return HWPEntry(key, try normalized(entry.value))
            })
        default: return value
        }
    }
}
