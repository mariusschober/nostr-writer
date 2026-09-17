import Foundation

/// Typed wire domains shared by the fixed native protocol implementation.
enum HWPProtocolValues {
    static let maximumInteger: Int64 = 9_007_199_254_740_991
    static let statementFields = "document media_type scope release captures target_capture lineage mode author nonce"
    static let releaseFields = "algorithm claim artifacts capture_profiles protocol stage validation"
    static let dossierFields = "stage claim model decision_policy program capture_profiles allowed_domains risk_target coverage_target confidence reports candidate"
    static let artifactNames = ["algorithm_spec", "program", "model", "decision_policy", "evidence_adapter", "output_contract"]
    static let spaces: Set<UInt32> = [9,10,11,12,13,32,0x85,0xa0,0x1680,0x2000,0x2001,0x2002,0x2003,0x2004,0x2005,0x2006,0x2007,0x2008,0x2009,0x200a,0x2028,0x2029,0x202f,0x205f,0x3000]

    static func need(_ condition: Bool, _ reason: String) throws { if !condition { throw HWPReject(reason) } }
    static func field(_ value: HWPValue, _ name: String) throws -> HWPValue {
        guard let found = value.field(name) else { throw HWPReject("object-fields") }; return found
    }
    static func fields(_ value: HWPValue, _ names: String) throws { try value.requireFields(names.split(separator: " ").map(String.init)) }
    static func typed(_ value: HWPValue, _ type: String, _ names: String) throws { try value.requireType(type, fields: names.split(separator: " ").map(String.init)) }
    static func integer(_ value: HWPValue?, low: Int64 = 0, high: Int64 = maximumInteger) throws -> Int64 {
        let result: Int64
        switch value {
        case .unsigned(let n) where n <= UInt64(Int64.max): result = Int64(n)
        case .negative(let n) where n < 0: result = n
        default: throw HWPReject("integer-domain")
        }
        try need(low <= result && result <= high, "integer-domain"); return result
    }
    static func bytes(_ value: HWPValue?, length: Int? = nil) throws -> Data {
        guard case .bytes(let raw) = value, raw.count <= HWPCBOR.maximumBytes else { throw HWPReject("byte-string-domain") }
        try need(length == nil || length == raw.count, "byte-string-length"); return raw
    }
    static func text(_ value: HWPValue?, minimum: Int = 0, maximum: Int = HWPCBOR.maximumBytes, reason: String = "text-domain") throws -> AlgorithmText {
        guard case .text(let raw) = value, raw.count <= HWPCBOR.maximumBytes else { throw HWPReject(reason) }
        let text = try AlgorithmText(utf8: raw)
        try need(minimum <= text.count && text.count <= maximum, reason); return text
    }
    static func array(_ value: HWPValue?, minimum: Int = 0, maximum: Int = HWPCBOR.maximumItems, reason: String = "array-domain") throws -> [HWPValue] {
        guard case .array(let values) = value, minimum <= values.count, values.count <= maximum else { throw HWPReject(reason) }
        return values
    }
    static func object(_ fields: [String: HWPValue]) -> HWPValue { .map(fields.map { HWPEntry(.text($0.key), $0.value) }) }
    static func reference(_ value: HWPValue?) throws -> HWPReference {
        guard let value else { throw HWPReject("object-fields") }; return try HWPReference(value: value)
    }
    static func references(_ value: HWPValue?, minimum: Int = 0, maximum: Int = 4096) throws -> [HWPReference] {
        let values = try array(value, minimum: minimum, maximum: maximum, reason: "reference-list-size")
        var result: [HWPReference] = [], previous: Data?
        for value in values {
            try Task.checkCancellation()
            let ref = try HWPReference(value: value)
            if let previous { try need(previous.lexicographicallyPrecedes(ref.sha256), "reference-order-or-duplicate") }
            result.append(ref); previous = ref.sha256
        }
        return result
    }
    static func sortedReferences(_ values: some Sequence<HWPReference>) -> [HWPReference] { values.sorted { $0.sha256.lexicographicallyPrecedes($1.sha256) } }
    static func referenceArray(_ values: some Sequence<HWPReference>) -> HWPValue { .array(values.map(\.value)) }
    static func texts(_ value: HWPValue?, minimum: Int = 1, maximum: Int = 4096) throws -> [AlgorithmText] {
        let values = try array(value, minimum: minimum, maximum: maximum, reason: "text-list")
        let result = try values.map { try text($0, minimum: 1, reason: "text-list") }
        try need(result == Set(result).sorted(), "text-list-order"); return result
    }
    static func jsonDomain(_ value: HWPValue, depth: Int = 0) throws {
        try Task.checkCancellation(); try need(depth <= 32, "adapter-depth")
        switch value {
        case .null, .boolean: return
        case .unsigned, .negative: _ = try integer(value, low: -maximumInteger)
        case .text: _ = try text(value)
        case .array(let values):
            try need(values.count <= 1_000_000, "adapter-items")
            for value in values { try jsonDomain(value, depth: depth + 1) }
        case .map(let entries):
            var keys: Set<AlgorithmText> = []
            for entry in entries {
                let key = try text(entry.key, reason: "adapter-json-domain")
                try need(keys.insert(key).inserted, "adapter-json-domain")
                try jsonDomain(entry.value, depth: depth + 1)
            }
        default: throw HWPReject("adapter-json-domain")
        }
    }
}
