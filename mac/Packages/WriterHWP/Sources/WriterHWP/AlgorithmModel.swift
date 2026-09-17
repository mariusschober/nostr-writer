import Foundation
import BigInt

/// Python-compatible integer operations for deterministic inference. No Double
/// participates in features, support distance, tree decisions, or aggregation.
public enum HWPFixedPoint {
    public static let q: Int64 = 10_000
    public static func floorDivide(_ numerator: BigInt, _ denominator: BigInt) throws -> BigInt {
        guard denominator != 0 else { throw HWPReject("INTEGER_DIVISION") }
        let quotient = numerator / denominator, remainder = numerator % denominator
        return remainder != 0 && numerator.sign != denominator.sign ? quotient - 1 : quotient
    }
    public static func ratio(_ numerator: BigInt, _ denominator: BigInt) throws -> Int64 {
        if denominator == 0 { return 0 }
        let value = try floorDivide(BigInt(q) * numerator, denominator)
        return Int64(max(BigInt(-q), min(BigInt(q), value)))
    }
    public static func scale(_ value: BigInt, cap: Int64) throws -> Int64 {
        guard cap > 0 else { throw HWPReject("INTEGER_DOMAIN") }
        return try ratio(min(max(value, 0), BigInt(cap)), BigInt(cap))
    }
    public static func quantile(_ values: [Int64], numerator: Int, denominator: Int = 100) throws -> Int64 {
        guard denominator > 0, (0...denominator).contains(numerator) else { throw HWPReject("INTEGER_DOMAIN") }
        if values.isEmpty { return 0 }
        let position = max(BigInt(0), (BigInt(values.count) * BigInt(numerator) + BigInt(denominator) - 1) / BigInt(denominator) - 1)
        guard let index = Int(exactly: position), index < values.count else { throw HWPReject("INTEGER_DOMAIN") }
        return values.sorted()[index]
    }
    public static func correlation(_ xs: [Int64], _ ys: [Int64]) throws -> Int64 {
        guard xs.count == ys.count else { throw HWPReject("FEATURE_ALIGNMENT") }
        if xs.count < 3 { return 0 }
        let n = BigInt(xs.count), sx = xs.reduce(BigInt(0)) { $0 + BigInt($1) }, sy = ys.reduce(BigInt(0)) { $0 + BigInt($1) }
        var aa = BigInt(0), bb = BigInt(0), ab = BigInt(0)
        for (x, y) in zip(xs, ys) {
            try Task.checkCancellation()
            let a = n * BigInt(x) - sx, b = n * BigInt(y) - sy
            aa += a * a; bb += b * b; ab += a * b
        }
        return try ratio(ab, (aa * bb).squareRoot())
    }
}

public struct HWPFeatureVector: Sendable {
    public let values: [Int64]
    public init(names: [String], values: [Int64]) throws {
        guard names == HWPFeatureSchema.names, values.count == names.count,
              values.allSatisfy({ (-10_000...10_000).contains($0) }) else { throw HWPReject("FEATURE_SCHEMA") }
        self.values = values
    }
}

public struct HWPModelEvaluation: Equatable, Sendable {
    public let score: Int64
    public let supported: Bool
    public let heads: [String: Int64]
    public let supportDistance: Int64
    public let supportNumerator: Int
    public let supportDenominator: Int
    public var details: HWPValue {
        .map([
            HWPEntry(.text("heads"), .map(heads.sorted { $0.key < $1.key }.map { HWPEntry(.text($0.key), .integer($0.value)) })),
            HWPEntry(.text("support_distance"), .integer(supportDistance)),
            HWPEntry(.text("support_rank"), .array([.unsigned(UInt64(supportNumerator)), .unsigned(UInt64(supportDenominator))]))
        ])
    }
}

/// Validation covers every branch, including branches not reached by a vector.
/// A validated model is computation input only; it is never an approval or trust policy.
public struct HWPAlgorithmModel: Sendable {
    public static let heads = ["transcription", "automation", "simulation", "mixed"]
    public static let scoreFloor: Int64 = -1_000_000_000
    private indirect enum Tree: Sendable {
        case leaf(Int64)
        case branch(Int, Int64, Tree, Tree)
        func evaluate(_ values: [Int64]) -> Int64 {
            switch self {
            case .leaf(let score): return score
            case .branch(let index, let threshold, let left, let right):
                return (values[index] <= threshold ? left : right).evaluate(values)
            }
        }
    }
    private struct Domain: Sendable {
        let heads: [String: [Tree]]
        let scales: [Int64]
        let prototypes: [[Int64]]
        let calibration: [Int64]
    }
    public let purpose: String
    public let domainNames: Set<AlgorithmText>
    private let domains: [AlgorithmText: Domain]

    public init(_ value: HWPValue) throws {
        typealias V = HWPAlgorithmValues
        try V.shape(value, required: ["version", "purpose", "features", "domains"], optional: ["training"])
        try V.need(value.field("version") == .text("hwp-a-model/v0"), "MODEL_VERSION")
        let purpose = try V.text(value.field("purpose")).string
        try V.need(["fixture", "research", "validated-release"].contains(purpose), "MODEL_PURPOSE")
        guard value.field("features") == .array(HWPFeatureSchema.names.map { .text($0) }) else { throw HWPReject("MODEL_FEATURE_SCHEMA") }
        let rawDomains = try V.object(value.field("domains"), reason: "MODEL_DOMAIN_LIMIT")
        try V.need((1...128).contains(rawDomains.count), "MODEL_DOMAIN_LIMIT")
        var domains: [AlgorithmText: Domain] = [:]
        for (name, artifact) in rawDomains {
            try Task.checkCancellation()
            let parts = name.string.split(separator: "|", omittingEmptySubsequences: false)
            try V.need(name.count <= 256 && parts.count == 4, "MODEL_DOMAIN")
            try V.need(["keyboard", "touch-tap", "ime", "gesture"].contains(String(parts[0])) && !parts[1].isEmpty && !parts[2].isEmpty && ["birth", "retained", "layout", "global"].contains(String(parts[3])), "MODEL_DOMAIN")
            try V.shape(artifact, required: ["heads", "scales", "prototypes", "support_calibration"])
            let rawHeads = try V.object(artifact.field("heads"), reason: "MODEL_HEADS")
            try V.need(Set(rawHeads.keys) == Set(Self.heads.map(AlgorithmText.init)), "MODEL_HEADS")
            var heads: [String: [Tree]] = [:]
            for head in Self.heads {
                let trees = try V.array(rawHeads[AlgorithmText(head)], reason: "TREE_COUNT")
                try V.need(trees.count == 32, "TREE_COUNT")
                heads[head] = try trees.map { try Self.tree($0, depth: 0) }
            }
            let scales = try Self.vector(artifact.field("scales"), low: 500, high: 20_000)
            let rawPrototypes = try V.array(artifact.field("prototypes"), reason: "PROTOTYPE_COUNT")
            try V.need((1...128).contains(rawPrototypes.count), "PROTOTYPE_COUNT")
            let prototypes = try rawPrototypes.map { try Self.vector($0, low: -10_000, high: 10_000) }
            let rawCalibration = try V.array(artifact.field("support_calibration"), reason: "SUPPORT_CALIBRATION_LIMIT")
            try V.need(rawCalibration.count <= 100_000, "SUPPORT_CALIBRATION_LIMIT")
            let calibration = try rawCalibration.map { try V.integer($0, high: 1_000_000_000) }
            domains[name] = Domain(heads: heads, scales: scales, prototypes: prototypes, calibration: calibration)
        }
        self.purpose = purpose; self.domains = domains; self.domainNames = Set(domains.keys)
    }

    private static func vector(_ value: HWPValue?, low: Int64, high: Int64) throws -> [Int64] {
        let items = try HWPAlgorithmValues.array(value, reason: "SUPPORT_DIMENSION")
        try HWPAlgorithmValues.need(items.count == HWPFeatureSchema.names.count, "SUPPORT_DIMENSION")
        return try items.map { try HWPAlgorithmValues.integer($0, low: low, high: high) }
    }
    private static func tree(_ value: HWPValue, depth: Int) throws -> Tree {
        typealias V = HWPAlgorithmValues
        _ = try V.object(value, reason: "TREE_NODE")
        if let score = value.field("value") {
            try V.shape(value, required: ["value"])
            return .leaf(try V.integer(score, low: -1250, high: 1250))
        }
        try V.need(depth < 2, "TREE_DEPTH")
        try V.shape(value, required: ["feature", "threshold", "left", "right"])
        let feature = try V.integer(value.field("feature"), high: Int64(HWPFeatureSchema.names.count - 1))
        let threshold = try V.integer(value.field("threshold"), low: -10_000, high: 10_000)
        guard let left = value.field("left"), let right = value.field("right") else { throw HWPReject("OBJECT_FIELDS") }
        return try .branch(Int(feature), threshold, tree(left, depth: depth + 1), tree(right, depth: depth + 1))
    }

    public func evaluate(_ features: HWPFeatureVector, domain: AlgorithmText) throws -> HWPModelEvaluation {
        guard let artifact = domains[domain] else { throw HWPReject("UNSUPPORTED_DOMAIN") }
        var margins: [String: Int64] = [:]
        for name in Self.heads {
            try Task.checkCancellation()
            guard let trees = artifact.heads[name] else { throw HWPReject("MISSING_ATTACK_HEAD") }
            margins[name] = trees.reduce(0) { $0 + $1.evaluate(features.values) }
        }
        var distances: [Int64] = []
        for prototype in artifact.prototypes {
            try Task.checkCancellation()
            var total = BigInt(0)
            for (index, x) in features.values.enumerated() {
                total += BigInt(10_000) * abs(BigInt(x) - BigInt(prototype[index])) / BigInt(artifact.scales[index])
            }
            guard let d = Int64(exactly: total / BigInt(features.values.count)) else { throw HWPReject("INTEGER_DOMAIN") }
            distances.append(d)
        }
        distances.sort()
        let distance = distances[min(4, distances.count - 1)]
        let numerator = 1 + artifact.calibration.filter { $0 >= distance }.count, denominator = 1 + artifact.calibration.count
        return HWPModelEvaluation(score: margins.values.min() ?? Self.scoreFloor,
                                  supported: artifact.calibration.count >= 99 && 100 * numerator > denominator,
                                  heads: margins, supportDistance: distance,
                                  supportNumerator: numerator, supportDenominator: denominator)
    }
}
