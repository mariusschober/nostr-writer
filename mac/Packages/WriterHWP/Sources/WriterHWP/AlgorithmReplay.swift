import Foundation

// Native port of frozen `protocol/v0/hwp0/algorithm/replay.py` (457 lines).
//
// Scope: deterministic Unicode-scalar replay, exact origin tracking and evidence
// windows for one structurally valid bundle. This module performs no capture
// authentication, no crypto, no admission and no publication. A valid trace is
// not authenticated capture and is not proof of composition.
//
// Identity rules: record ids, tokens, roots, run ids, path ids, languages and
// every compared text are exact scalar/UTF-8 byte sequences (`AlgorithmText`).
// Swift `String` equality is never used for untrusted data, because canonical
// equivalence would collapse distinct record identity. Only the fixed ASCII
// enum names below (validated by exact byte match at parse time) use `String`.

// MARK: - Fixed ASCII domain enumerations

/// Observation kinds from frozen `OBS_KINDS`, `STARTS`, `ENDS` and `UPDATES`.
public enum HWPObservationKind: String, Sendable, CaseIterable {
    case press
    case release
    case repeatKey = "repeat"
    case command
    case focusOut = "focus_out"
    case focusIn = "focus_in"
    case suspend
    case resume
    case gap
    case delivery
    case touchDown = "touch_down"
    case touchUp = "touch_up"
    case touchMove = "touch_move"
    case imeStart = "ime_start"
    case imeUpdate = "ime_update"
    case imeCommit = "ime_commit"
    case gestureStart = "gesture_start"
    case gestureUpdate = "gesture_update"
    case gestureEnd = "gesture_end"

    /// Frozen `STARTS` (the value set of `ENDS`).
    public var isStart: Bool {
        switch self {
        case .press, .touchDown, .imeStart, .gestureStart: true
        default: false
        }
    }

    /// Frozen `ENDS` key set.
    public var isEnd: Bool {
        switch self {
        case .release, .touchUp, .imeCommit, .gestureEnd: true
        default: false
        }
    }

    /// Frozen `UPDATES` key set.
    public var isUpdate: Bool {
        switch self {
        case .touchMove, .imeUpdate, .gestureUpdate: true
        default: false
        }
    }

    /// Counted into `prefix_barriers`.
    public var isBarrier: Bool {
        switch self {
        case .focusOut, .suspend, .gap: true
        default: false
        }
    }

    /// Frozen `ENDS[self]`; `nil` for non-end kinds.
    public var matchingStart: HWPObservationKind? {
        switch self {
        case .release: .press
        case .touchUp: .touchDown
        case .imeCommit: .imeStart
        case .gestureEnd: .gestureStart
        default: nil
        }
    }

    /// Frozen `UPDATES[self]`; `nil` for non-update kinds.
    public var matchingUpdateStart: HWPObservationKind? {
        switch self {
        case .touchMove: .touchDown
        case .imeUpdate: .imeStart
        case .gestureUpdate: .gestureStart
        default: nil
        }
    }
}

/// Observation capture sources accepted by the frozen parser.
public enum HWPObservationSource: String, Sendable, CaseIterable {
    case device, synthetic, unknown
}

/// Frozen `PROFILES` keys with their `(first_cause_kind, insert_limit)` entries.
public enum HWPProfile: String, Sendable, CaseIterable {
    case keyboard
    case touchTap = "touch-tap"
    case ime
    case gesture

    /// `PROFILES[profile][0]` used for non-keyboard direct splices.
    public var directCauseKind: HWPObservationKind {
        switch self {
        case .keyboard: .press
        case .touchTap: .touchDown
        case .ime: .imeCommit
        case .gesture: .gestureEnd
        }
    }

    /// `PROFILES[profile][1]`: maximum inserted scalars per cause.
    public var maximumDirectInsertionPerCause: Int64 {
        switch self {
        case .keyboard, .touchTap: 8
        case .ime: 256
        case .gesture: 64
        }
    }

    /// Frozen `DIRECT_CAUSE`: keyboard accepts `press`/`repeat`, others one kind.
    public func allowsDirectCause(_ kind: HWPObservationKind) -> Bool {
        self == .keyboard ? (kind == .press || kind == .repeatKey) : kind == directCauseKind
    }
}

/// Frozen `Atom.kind`.
public enum HWPAtomKind: String, Sendable, CaseIterable {
    case candidate, external, derived
}

/// Frozen `Effect.source` and `Transaction.source` values.
public enum HWPTextSource: String, Sendable, CaseIterable {
    case direct, paste, generated, unknown, spelling, control

    /// Frozen `TEXT_SOURCE` allowed set, which depends on the operation.
    public static func allowed(for operation: HWPOp) -> Set<HWPTextSource> {
        operation == .splice
            ? [.direct, .paste, .generated, .unknown, .spelling]
            : [.control]
    }
}

/// Frozen transaction operation names.
public enum HWPOp: String, Sendable, CaseIterable {
    case splice, copy, move, undo, redo, navigate

    /// Frozen `fields` table: op-specific transaction keys.
    var specificFields: Set<String> {
        switch self {
        case .splice: ["start", "end", "text", "deleted", "source"]
        case .copy: ["from_doc", "start", "end", "to"]
        case .move: ["start", "end", "to"]
        case .undo, .redo: ["ref"]
        case .navigate: ["start", "end"]
        }
    }
}

/// Frozen `Unit.view`.
public enum HWPUnitView: String, Sendable, CaseIterable {
    case birth, layout, retained, global
}

// MARK: - Public model

/// Exact atom record (frozen `AlgorithmReplay.Atom`).
public struct AlgorithmAtom: Sendable, Equatable {
    public let aid: AlgorithmText
    public let char: AlgorithmText
    public let roots: Set<AlgorithmText>
    public let kind: HWPAtomKind
    public let home: AlgorithmText
    public let birth: Int64
    public let run: AlgorithmText
    public let profile: HWPProfile
    public let requirements: Set<AlgorithmText>
    public let spelling: Bool
}

/// Exact parsed observation. `basis` is present only for `ime_commit` inputs and
/// `effect` only for `delivery` inputs, matching frozen `UNEXPECTED_BASIS` and
/// `DELIVERY_FIELDS`.
public struct AlgorithmObservation: Sendable {
    public let index: Int64
    public let time: Int64
    public let sequence: Int64
    public let kind: HWPObservationKind
    public let token: AlgorithmText
    public let source: HWPObservationSource
    public let profile: HWPProfile
    public let basis: [Int64]?
    public let effect: HWPValue?
}

/// Exact effect record (frozen `AlgorithmReplay.Effect`).
///
/// `ages` is exposed sorted ascending. Frozen Python builds it by iterating a
/// `set`, so no Python order is stable or meaningful; frozen feature code
/// consumes it order-independently.
public struct AlgorithmEffect: Sendable, Equatable {
    public let index: Int64
    public let time: Int64
    public let op: HWPOp
    public let source: HWPTextSource
    public let profile: HWPProfile
    public let run: AlgorithmText
    public let pos: Int64
    public let beforeLength: Int64
    public let old: AlgorithmText
    public let new: AlgorithmText
    public let born: [AlgorithmText]
    public let touched: Set<AlgorithmText>
    public let causes: [Int64]
    public let preceding: Int64
    public let navigation: Int64
    public let ages: [Int64]
    public let barrier: Bool
}

/// Ordered `(run, atoms)` pair; frozen `Document.runs` is an insertion-ordered
/// dict and its order decides birth-unit order.
public struct AlgorithmRun: Sendable, Equatable {
    public let run: AlgorithmText
    public let atoms: [AlgorithmText]
}

/// Ordered `(observation index, duration)` pair; frozen `Document.durations` is
/// an insertion-ordered dict keyed by an observation index.
public struct AlgorithmDuration: Sendable, Equatable {
    public let index: Int64
    public let duration: Int64
}

/// Exact document record (frozen `AlgorithmReplay.Document`).
public struct AlgorithmDocument: Sendable {
    public let did: AlgorithmText
    public let language: AlgorithmText
    public let resolution: Int64
    public let observations: [AlgorithmObservation]
    public let effects: [AlgorithmEffect]
    public let live: [AlgorithmText]
    public let text: AlgorithmText
    public let gap: Bool
    public let runs: [AlgorithmRun]
    /// Frozen `dict(paths)`: profile to path id, insertion-ordered by `pathOrder`.
    public let paths: [HWPProfile: AlgorithmText]
    public let pathOrder: [HWPProfile]
    public let durations: [AlgorithmDuration]
    public let unsafeControl: Bool
}

/// One entry of frozen `Corpus.external`.
public struct AlgorithmExternal: Sendable, Equatable {
    public let owner: AlgorithmText
    public let transaction: Int64
    public let text: AlgorithmText
}

/// Exact unit record (frozen `AlgorithmReplay.Unit`).
public struct AlgorithmUnit: Sendable, Equatable {
    public let uid: AlgorithmText
    public let doc: AlgorithmText
    public let view: HWPUnitView
    public let roots: [AlgorithmText]
    public let profile: HWPProfile
    public let language: AlgorithmText
}

/// Mutable replay corpus. Deliberately a reference type: `related` charges
/// `analysisEdges` against the corpus, exactly as frozen `Corpus` does. Confine
/// one corpus to one assessment worker; it is not `Sendable`.
public final class AlgorithmCorpus {
    public private(set) var documents: [AlgorithmText: AlgorithmDocument] = [:]
    /// Frozen dict insertion order for `documents`.
    public private(set) var documentOrder: [AlgorithmText] = []
    public private(set) var atoms: [AlgorithmText: AlgorithmAtom] = [:]
    /// Frozen `root_effects`: every `(document, effect index)` that touched a root.
    public private(set) var rootEffects: [AlgorithmText: [(document: AlgorithmText, index: Int64)]] = [:]
    public private(set) var external: [AlgorithmExternal] = []
    public private(set) var externalScalars: Int64 = 0
    public private(set) var effectEdges: Int64 = 0
    public private(set) var analysisEdges: Int64 = 0
    public private(set) var storedIDs: Int64 = 0

    init() {}

    /// Frozen `Corpus.text`: concatenate atom characters in the given order.
    public func text(_ ids: [AlgorithmText]) throws -> AlgorithmText {
        var bytes = Data()
        for (index, aid) in ids.enumerated() {
            if index % 1024 == 0 { try Task.checkCancellation() }
            guard let atom = atoms[aid] else { throw HWPReject("UNKNOWN_ATOM") }
            bytes.append(atom.char.utf8)
        }
        return try AlgorithmText(utf8: bytes)
    }

    // Frozen-faithful mutation points, reachable only from this file.
    func addDocument(_ document: AlgorithmDocument) {
        if documents.updateValue(document, forKey: document.did) == nil {
            documentOrder.append(document.did)
        }
    }
    func addAtom(_ atom: AlgorithmAtom) { atoms[atom.aid] = atom }
    func addRootEffect(_ root: AlgorithmText, document: AlgorithmText, index: Int64) {
        rootEffects[root, default: []].append((document, index))
    }
    func addExternal(_ entry: AlgorithmExternal) { external.append(entry) }
    func chargeExternalScalars(_ count: Int64) { externalScalars += count }
    func chargeEffectEdges(_ count: Int64) { effectEdges += count }
    func chargeAnalysisEdges(_ count: Int64) { analysisEdges += count }
    func chargeStoredIDs(_ count: Int64) { storedIDs += count }
}

// MARK: - Replay

public enum HWPReplay {
    // MARK: Frozen limits

    public static let maxScalars: Int64 = 200_000
    public static let maxEvents: Int64 = 500_000
    public static let maxDocuments: Int64 = 32
    public static let maxAtoms: Int64 = 1_000_000
    public static let maxIDsStored: Int64 = 5_000_000
    public static let maxEffectEdges: Int64 = 5_000_000
    public static let maxExternalScalars: Int64 = 1_000_000
    public static let maxAnalysisEdges: Int64 = 50_000_000
    public static let minimumRoots: Int64 = 64
    public static let runGap: Int64 = 120_000_000
    public static let maxCauseDelay: Int64 = 250_000
    public static let maximumInteger: Int64 = HWPAlgorithmValues.maximumInteger
    /// Frozen `WINDOWS`.
    public static let windows: [(width: Int64, stride: Int64)] = [(64, 32), (256, 128)]
    /// Frozen `1024` bound shared by `CAUSES` and `IME_BASIS`.
    static let maxCauses = 1_024

    /// Frozen `SPACE`.
    static let spaceScalars: Set<UInt32> = [
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x0085, 0x00A0,
        0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007,
        0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
    ]
    /// Frozen `'\n\r\u2028\u2029'`.
    static let lineBreakScalars: Set<UInt32> = [0x000A, 0x000D, 0x2028, 0x2029]
    /// Frozen `'.!?。！？'`.
    static let stopScalars: Set<UInt32> = [0x002E, 0x0021, 0x003F, 0x3002, 0xFF01, 0xFF1F]

    static let bundleFields: Set<String> = ["version", "documents", "target"]
    static let documentFields: Set<String> = [
        "id", "language", "resolution_us", "paths", "observations", "transactions", "final_text",
    ]
    static let observationFields: Set<String> = [
        "i", "t", "seq", "kind", "token", "source", "profile",
    ]
    static let observationOptionalFields: Set<String> = ["basis", "effect"]
    static let transactionCommonFields: Set<String> = [
        "i", "t", "seq", "op", "profile", "causes", "delivery",
    ]
    static let deliveryContractExcluded: Set<String> = ["i", "t", "seq", "delivery"]
    /// Frozen `CAUSE_PROFILE` kinds.
    static let causeKinds: Set<HWPObservationKind> = [
        .press, .repeatKey, .touchDown, .imeCommit, .gestureEnd, .command,
    ]

    // MARK: Primitives (frozen `need` / `num` / `string` / `shape`)

    @inline(__always)
    static func need(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw HWPReject(reason) }
    }

    /// Frozen `num`. Rejects booleans, non-integers and out-of-range values.
    static func num(_ value: HWPValue?, low: Int64 = 0, high: Int64 = maximumInteger) throws -> Int64 {
        try HWPAlgorithmValues.integer(value, low: low, high: high)
    }

    /// Frozen `string`. Length is a scalar count; text is exact UTF-8 bytes.
    static func string(_ value: HWPValue?, maximum: Int64 = maxScalars) throws -> AlgorithmText {
        try HWPAlgorithmValues.text(value, maximum: Int(maximum))
    }

    /// Frozen `shape`.
    static func shape(_ value: HWPValue?, required: Set<String>, optional: Set<String> = []) throws {
        try HWPAlgorithmValues.shape(value, required: required, optional: optional)
    }

    /// Frozen map conversion for `[AlgorithmText: HWPValue]` domains.
    static func map(_ value: HWPValue?) throws -> [AlgorithmText: HWPValue] {
        try HWPAlgorithmValues.object(value)
    }

    static func textKey(_ key: HWPValue) -> AlgorithmText? {
        guard case .text(let bytes) = key else { return nil }
        return try? AlgorithmText(utf8: bytes)
    }

    /// Exact field lookup on a raw map without validating the field type.
    /// Duplicate keys resolve last-wins, matching a decoded Python `dict`.
    static func rawField(_ value: HWPValue?, _ name: String) -> HWPValue? {
        guard let value, case .map(let entries) = value else { return nil }
        let key = AlgorithmText(name)
        for entry in entries.reversed() where textKey(entry.key) == key { return entry.value }
        return nil
    }

    /// A Python `int` ordering view. Exact for every integer the frozen CBOR
    /// decoder can produce, and used only by frozen `GLOBAL_CLOCK`, which
    /// compares raw `t` values before their type is validated.
    enum PyInt: Comparable {
        case negative(Int64)
        case small(UInt64)
        case large(UInt64)

        static func < (left: PyInt, right: PyInt) -> Bool {
            switch (left, right) {
            case (.negative(let a), .negative(let b)): a < b
            case (.negative, _): true
            case (_, .negative): false
            case (.small(let a), .small(let b)): a < b
            case (.small(let a), .large(let b)): a < b
            case (.large, .small): false
            case (.large(let a), .large(let b)): a < b
            }
        }
    }

    /// Python's numeric view of a raw value. `nil` means the comparison would
    /// raise `TypeError` in frozen Python (unsupported raw `t`).
    static func pythonInt(_ value: HWPValue?) -> PyInt? {
        switch value {
        case .unsigned(let number): number <= UInt64(Int64.max) ? .small(number) : .large(number)
        case .negative(let number) where number < 0: .negative(number)
        case .boolean(let flag): .small(flag ? 1 : 0)
        default: nil
        }
    }

    /// Frozen `type(x) is int`: any raw integer, of unbounded magnitude.
    struct RawInteger: Hashable {
        let negative: Bool
        let magnitude: UInt64
        init?(_ value: HWPValue) {
            switch value {
            case .unsigned(let number): self.init(negative: false, magnitude: number)
            case .negative(let number) where number < 0:
                self.init(negative: true, magnitude: UInt64(bitPattern: number))
            default: return nil
            }
        }
        private init(negative: Bool, magnitude: UInt64) {
            self.negative = negative
            self.magnitude = magnitude
        }
    }

    /// Frozen `CAUSES` / `IME_BASIS` list validation: bounded, all integers,
    /// no duplicates. JSON/CBOR canonical maps make duplicate list entries the
    /// only duplicate concern here.
    static func integerList(_ value: HWPValue?, typeReason: String, duplicateReason: String,
                            maximum: Int) throws -> [HWPValue] {
        let items = try HWPAlgorithmValues.array(value, reason: typeReason)
        try need(!items.isEmpty && items.count <= maximum, typeReason)
        var keys: Set<RawInteger> = []
        keys.reserveCapacity(items.count)
        for item in items {
            guard let key = RawInteger(item) else { throw HWPReject(typeReason) }
            try need(keys.insert(key).inserted, duplicateReason)
        }
        return items
    }

    /// Frozen `utf8_offsets`.
    static func utf8Offsets(_ text: AlgorithmText) -> [Int64] {
        var offsets: [Int64] = [0]
        var total: Int64 = 0
        for scalar in text.scalars {
            switch scalar {
            case 0..<0x80: total += 1
            case 0x80..<0x800: total += 2
            case 0x800..<0x1_0000: total += 3
            default: total += 4
            }
            offsets.append(total)
        }
        return offsets
    }

    /// Frozen `scalar_range`: UTF-8 byte offsets to scalar indices.
    public static func scalarRange(_ text: AlgorithmText, start: Int64, end: Int64) throws
        -> (start: Int64, end: Int64) {
        let offsets = utf8Offsets(text)
        guard let last = offsets.last else { throw HWPReject("TEXT_DOMAIN") }
        _ = try num(HWPValue.integer(start), low: 0, high: last)
        _ = try num(HWPValue.integer(end), low: start, high: last)
        var table: [Int64: Int64] = [:]
        table.reserveCapacity(offsets.count)
        for (index, offset) in offsets.enumerated() { table[offset] = Int64(index) }
        guard let lower = table[start], let upper = table[end] else {
            throw HWPReject("SPLIT_UNICODE_SCALAR")
        }
        return (lower, upper)
    }

    /// Frozen `edit_distance` over scalars.
    public static func editDistance(_ a: AlgorithmText, _ b: AlgorithmText) throws -> Int64 {
        let left = a.scalars, right = b.scalars
        try need(left.count <= 32 && right.count <= 32, "SPELLING_LIMIT")
        var row = Array(0...Int64(right.count))
        for (index, leftScalar) in left.enumerated() {
            var next: [Int64] = [Int64(index) + 1]
            next.reserveCapacity(right.count + 1)
            for (offset, rightScalar) in right.enumerated() {
                next.append(min(
                    next[offset] + 1,
                    row[offset + 1] + 1,
                    row[offset] + (leftScalar == rightScalar ? 0 : 1)))
            }
            row = next
        }
        return row[row.count - 1]
    }

    // MARK: Frozen `windows`

    /// Frozen `windows`: stride windows plus the final tail window.
    public static func windows<Element>(_ items: [Element], width: Int64, stride: Int64) throws -> [[Element]] {
        try need(width > 0 && stride > 0, "WINDOW_PARAMETERS")
        guard !items.isEmpty else { return [] }
        let count = Int64(items.count)
        if count <= width { return [items] }
        var starts: Set<Int64> = []
        var start: Int64 = 0
        while start <= count - width {
            try Task.checkCancellation()
            starts.insert(start)
            // Avoid overflow even for a public caller's exceptionally large stride.
            if stride > count - width - start { break }
            start += stride
        }
        starts.insert(count - width)
        return starts.sorted().map { offset in
            Array(items[Int(offset)..<Int(offset + width)])
        }
    }

    // MARK: Entry points

    /// Frozen `replay(bundle)`.
    public static func replay(_ bundle: HWPValue) throws -> AlgorithmCorpus {
        try shape(bundle, required: bundleFields)
        let fields = try map(bundle)
        guard let version = textKey(try requireField(fields, "version")),
              version == AlgorithmText("hwp-a/v0") else { throw HWPReject("VERSION") }
        let documents = try HWPAlgorithmValues.array(
            requireField(fields, "documents"), reason: "DOCUMENT_LIMIT")
        try need(!documents.isEmpty && Int64(documents.count) <= maxDocuments, "DOCUMENT_LIMIT")
        let corpus = AlgorithmCorpus()
        for document in documents {
            try replayDocument(document, into: corpus)
        }
        guard let targetValue = try? requireField(fields, "target"),
              case .text(let targetBytes) = targetValue,
              let target = try? AlgorithmText(utf8: targetBytes) else { throw HWPReject("TARGET") }
        try need(corpus.documents[target] != nil, "TARGET")
        return corpus
    }

    /// Frozen `make_units(c, did)`.
    public static func makeUnits(_ corpus: AlgorithmCorpus, document: AlgorithmText) throws
        -> (units: [AlgorithmUnit], members: [AlgorithmText: [AlgorithmText]]) {
        guard let d = corpus.documents[document] else { throw HWPReject("TARGET") }
        var out: [AlgorithmUnit] = []
        var members: [AlgorithmText: [AlgorithmText]] = [:]

        func add(_ view: HWPUnitView, _ group: AlgorithmText, _ roots: [AlgorithmText]) throws {
            for (width, stride) in windows {
                let slices = try windows(roots, width: width, stride: stride)
                for (number, slice) in slices.enumerated() {
                    try Task.checkCancellation()
                    guard let first = slice.first,
                          let atom = corpus.atoms[first] else { throw HWPReject("UNKNOWN_ATOM") }
                    var bytes = Data()
                    bytes.append(document.utf8)
                    bytes.append(contentsOf: Array("/\(view.rawValue)/".utf8))
                    bytes.append(group.utf8)
                    bytes.append(contentsOf: Array("/\(width)/\(number)".utf8))
                    let uid = try AlgorithmText(utf8: bytes)
                    out.append(AlgorithmUnit(uid: uid, doc: document, view: view, roots: slice,
                                             profile: atom.profile, language: d.language))
                    for root in slice { members[root, default: []].append(uid) }
                }
            }
        }

        // Birth units: frozen `for run, rr in d.runs.items()`.
        for bucket in d.runs {
            try add(.birth, bucket.run, bucket.atoms)
        }

        // Layout/retained grouping is defined from the home version, never from
        // a requested scope.
        var groups: [[AlgorithmText]] = []
        var buffer: [AlgorithmText] = []
        var seenRoots: Set<AlgorithmText> = []
        var currentRun: AlgorithmText?

        func flush() {
            if !buffer.isEmpty { groups.append(buffer) }
            buffer = []
            seenRoots = []
        }

        for aid in d.live {
            try Task.checkCancellation()
            guard let atom = corpus.atoms[aid] else { throw HWPReject("UNKNOWN_ATOM") }
            var rootsAreHome = !atom.roots.isEmpty
            for root in atom.roots where corpus.atoms[root]?.home != document {
                rootsAreHome = false
            }
            guard rootsAreHome else { flush(); currentRun = nil; continue }
            var rootRuns: Set<AlgorithmText> = []
            for root in atom.roots {
                guard let rootAtom = corpus.atoms[root] else { throw HWPReject("UNKNOWN_ATOM") }
                rootRuns.insert(rootAtom.run)
            }
            guard rootRuns.count == 1, let atomRun = rootRuns.first else {
                flush(); currentRun = nil; continue
            }
            if atomRun != currentRun { flush(); currentRun = atomRun }
            for root in try sortedByBirth(atom.roots, corpus) where !seenRoots.contains(root) {
                buffer.append(root)
                seenRoots.insert(root)
            }
        }
        flush()

        var seen: Set<[AlgorithmText]> = []
        for (index, group) in groups.enumerated() {
            if seen.contains(group) { continue }
            try add(.layout, AlgorithmText("\(index)"), group)
            try add(.retained, AlgorithmText("\(index)"), try sortedByBirth(group, corpus))
            seen.insert(group)
        }

        // Omnibus process check: one final-origin set per input profile, across
        // runs. Frozen `sorted(by_profile.items())` orders by profile name.
        var byProfile: [HWPProfile: Set<AlgorithmText>] = [:]
        for aid in d.live {
            guard let atom = corpus.atoms[aid] else { throw HWPReject("UNKNOWN_ATOM") }
            for root in atom.roots {
                guard let rootAtom = corpus.atoms[root] else { throw HWPReject("UNKNOWN_ATOM") }
                guard rootAtom.home == document else { continue }
                byProfile[rootAtom.profile, default: []].insert(root)
            }
        }
        for profile in byProfile.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let roots = byProfile[profile] else { continue }
            let ordered = try sortedByBirth(roots, corpus)
            guard !ordered.isEmpty else { continue }
            let uid = try joined([
                document.utf8,
                Data("/global/\(profile.rawValue)".utf8),
            ])
            out.append(AlgorithmUnit(uid: uid, doc: document, view: .global, roots: ordered,
                                     profile: profile, language: d.language))
            for root in ordered { members[root, default: []].append(uid) }
        }

        return (out, members)
    }

    /// Frozen `related(c, u)`. Charges `analysisEdges` against the corpus.
    public static func related(_ corpus: AlgorithmCorpus, unit: AlgorithmUnit) throws
        -> [AlgorithmEffect] {
        var charge: Int64 = 0
        for root in unit.roots {
            charge += Int64(corpus.rootEffects[root]?.count ?? 0)
        }
        corpus.chargeAnalysisEdges(charge)
        try need(corpus.analysisEdges <= maxAnalysisEdges, "ANALYSIS_WORK_LIMIT")

        var indices: Set<Int64> = []
        for root in unit.roots {
            for entry in corpus.rootEffects[root] ?? [] where entry.document == unit.doc {
                indices.insert(entry.index)
            }
        }
        guard let d = corpus.documents[unit.doc] else { throw HWPReject("TARGET") }
        var result: [AlgorithmEffect] = []
        for index in indices.sorted() {
            guard index >= 0, index < Int64(d.effects.count) else { continue }
            let effect = d.effects[Int(index)]
            if effect.op == .copy || effect.op == .navigate { continue }
            result.append(effect)
        }
        return result
    }

    /// Frozen `observed_source_matches(c, did)`.
    public static func observedSourceMatches(_ corpus: AlgorithmCorpus, document: AlgorithmText) throws
        -> Set<AlgorithmText> {
        var first: [AlgorithmText: Int64] = [:]
        for entry in corpus.external where entry.owner == document {
            try Task.checkCancellation()
            let scalars = entry.text.scalars
            for index in 0..<max(0, scalars.count - 31) {
                if index % 1024 == 0 { try Task.checkCancellation() }
                let shingle = try AlgorithmText(scalars: Array(scalars[index..<(index + 32)]))
                if let previous = first[shingle], previous <= entry.transaction { continue }
                first[shingle] = entry.transaction
            }
        }
        try need(Int64(first.count) <= maxExternalScalars, "SOURCE_INDEX_LIMIT")

        guard let d = corpus.documents[document] else { throw HWPReject("TARGET") }
        let documentScalars = d.text.scalars
        var blocked: Set<AlgorithmText> = []
        for index in 0..<max(0, documentScalars.count - 31) {
            try Task.checkCancellation()
            let shingle = try AlgorithmText(scalars: Array(documentScalars[index..<(index + 32)]))
            guard let exposedAt = first[shingle] else { continue }
            let window = Array(d.live[index..<(index + 32)])
            var allFresh = true
            for aid in window {
                guard let atom = corpus.atoms[aid], !atom.roots.isEmpty else { allFresh = false; break }
                for root in atom.roots {
                    guard let rootAtom = corpus.atoms[root],
                          rootAtom.home == document,
                          rootAtom.birth > exposedAt else { allFresh = false; break }
                }
                if !allFresh { break }
            }
            if allFresh { blocked.formUnion(window) }
        }
        return blocked
    }

    // MARK: Shared helpers

    static func requireField(_ fields: [AlgorithmText: HWPValue], _ name: String) throws -> HWPValue {
        guard let value = fields[AlgorithmText(name)] else { throw HWPReject("OBJECT_FIELDS") }
        return value
    }

    static func joined(_ parts: [Data]) throws -> AlgorithmText {
        var bytes = Data()
        for part in parts { bytes.append(part) }
        return try AlgorithmText(utf8: bytes)
    }

    /// Frozen `f'{did}:{i}:{j}'`.
    static func atomID(_ did: AlgorithmText, _ transaction: Int64, _ offset: Int64) throws
        -> AlgorithmText {
        try joined([did.utf8, Data(":\(transaction):\(offset)".utf8)])
    }

    static func enumValue<T: RawRepresentable>(_ value: HWPValue?, _ type: T.Type,
                                                reason: String) throws -> T where T.RawValue == String {
        guard case .text(let bytes) = value,
              let name = String(data: bytes, encoding: .utf8),
              let result = T(rawValue: name) else { throw HWPReject(reason) }
        return result
    }

    /// Frozen sort key `(birth, int(id.rsplit(':', 1)[1]))`.
    ///
    /// Atom ids are minted by this module as `<did>:<transaction>:<offset>`, and
    /// `did` is validated to exclude `:`, so the suffix always parses. A
    /// malformed id is unreachable outside memory corruption and fails closed.
    static func sortedByBirth(_ roots: some Sequence<AlgorithmText>,
                              _ corpus: AlgorithmCorpus) throws -> [AlgorithmText] {
        var keyed: [(birth: Int64, offset: Int64, value: AlgorithmText)] = []
        for root in roots {
            guard let atom = corpus.atoms[root] else { throw HWPReject("UNKNOWN_ATOM") }
            guard let suffix = trailingColonDecimal(root.utf8) else { throw HWPReject("ATOM_ID_FORMAT") }
            keyed.append((atom.birth, suffix, root))
        }
        keyed.sort { left, right in
            if left.birth != right.birth { return left.birth < right.birth }
            if left.offset != right.offset { return left.offset < right.offset }
            return left.value < right.value
        }
        return keyed.map(\.value)
    }

    /// Parse the decimal suffix after the final `:` of an atom id.
    static func trailingColonDecimal(_ bytes: Data) -> Int64? {
        var index = bytes.count - 1
        guard index >= 0 else { return nil }
        var value: Int64 = 0
        var multiplier: Int64 = 1
        var digits = 0
        while index >= 0 {
            let byte = bytes[bytes.startIndex + index]
            if byte == UInt8(ascii: ":") { return digits > 0 ? value : nil }
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            guard digits < 18 else { return nil }
            value += Int64(byte - UInt8(ascii: "0")) * multiplier
            multiplier *= 10
            digits += 1
            index -= 1
        }
        return nil
    }

    /// Key for frozen `(kind, token)` tuples. Tokens stay exact `AlgorithmText`.
    struct ObservationKey: Hashable {
        let prefix: HWPObservationKind
        let token: AlgorithmText
    }

    /// State frozen Python keeps for an open input episode.
    struct OpenEpisode {
        let index: Int64
        let time: Int64
        let sequence: Int64
        let source: HWPObservationSource
        let profile: HWPProfile
        let kind: HWPObservationKind
    }

    /// Undo/redo delta `(start_or_lo, removed, inserted, origin index)`.
    struct HistoryDelta {
        let position: Int64
        let removed: [AlgorithmText]
        let inserted: [AlgorithmText]
        let origin: Int64
    }

    // MARK: Frozen `parse_observations`

    static func parseObservations(_ value: HWPValue?, resolution: Int64) throws
        -> (observations: [AlgorithmObservation], gap: Bool) {
        let items = try HWPAlgorithmValues.array(value, reason: "OBSERVATION_LIMIT")
        try need(Int64(items.count) <= maxEvents, "OBSERVATION_LIMIT")

        var active: [ObservationKey: OpenEpisode] = [:]
        var usedTokens: Set<ObservationKey> = []
        var last: Int64 = 0
        var gap = false
        var focused = true
        var suspended = false
        var parsed: [AlgorithmObservation] = []
        parsed.reserveCapacity(items.count)

        for (position, item) in items.enumerated() {
            try Task.checkCancellation()
            try shape(item, required: observationFields, optional: observationOptionalFields)
            let fields = try map(item)
            let index = try num(try requireField(fields, "i"))
            try need(index == Int64(position), "OBSERVATION_SEQUENCE")
            let sequence = try num(try requireField(fields, "seq"))
            let time = try num(try requireField(fields, "t"))
            try need(time >= last && time % resolution == 0, "OBSERVATION_CLOCK")
            last = time
            let kind = try enumValue(try requireField(fields, "kind"), HWPObservationKind.self,
                                     reason: "OBSERVATION_KIND")
            let profile = try enumValue(try requireField(fields, "profile"), HWPProfile.self,
                                        reason: "PROFILE")
            let source = try enumValue(try requireField(fields, "source"),
                                       HWPObservationSource.self, reason: "OBSERVATION_SOURCE")
            let token = try string(try requireField(fields, "token"), maximum: 128)
            try need(!token.isEmpty, "TOKEN")

            var basis: [Int64]?

            switch kind {
            case .gap:
                gap = true
            case .focusOut:
                try need(focused, "FOCUS_STATE"); focused = false
            case .focusIn:
                try need(!focused, "FOCUS_STATE"); focused = true
            case .suspend:
                try need(!suspended, "SUSPEND_STATE"); suspended = true
            case .resume:
                try need(suspended, "SUSPEND_STATE"); suspended = false
            default:
                break
            }

            if kind.isStart {
                try need(focused && !suspended, "INPUT_OUTSIDE_OBSERVATION")
                let key = ObservationKey(prefix: kind, token: token)
                try need(!usedTokens.contains(key), "INPUT_TOKEN_REUSE")
                if kind == .imeStart {
                    try need(!active.keys.contains(where: { $0.prefix == .imeStart }), "OVERLAPPING_IME")
                }
                usedTokens.insert(key)
                active[key] = OpenEpisode(index: index, time: time, sequence: sequence,
                                          source: source, profile: profile, kind: kind)
            } else if kind.isEnd {
                if kind == .imeCommit || kind == .gestureEnd {
                    try need(focused && !suspended, "INPUT_OUTSIDE_OBSERVATION")
                }
                guard let startKind = kind.matchingStart else { throw HWPReject("OBSERVATION_KIND") }
                let key = ObservationKey(prefix: startKind, token: token)
                guard let begin = active.removeValue(forKey: key) else {
                    throw HWPReject("END_WITHOUT_START")
                }
                try need(begin.profile == profile && begin.source == source, "EPISODE_CHANGED")
                if kind == .imeCommit {
                    let raw = try integerList(fields[AlgorithmText("basis")], typeReason: "IME_BASIS",
                                              duplicateReason: "IME_BASIS", maximum: maxCauses)
                    var validated: [Int64] = []
                    validated.reserveCapacity(raw.count)
                    for element in raw {
                        let offset = try HWPAlgorithmValues.integer(
                            element, low: 0, high: Int64(position) - 1)
                        let motor = parsed[Int(offset)]
                        try need((motor.kind == .press || motor.kind == .touchDown)
                                 && begin.time <= motor.time && motor.time <= time
                                 && begin.sequence < motor.sequence && motor.sequence < sequence,
                                 "IME_MOTOR_BASIS")
                        try need(motor.source == source && motor.profile == profile,
                                 "IME_MOTOR_SOURCE")
                        validated.append(offset)
                    }
                    basis = validated
                }
            } else if kind == .repeatKey {
                try need(focused && !suspended, "INPUT_OUTSIDE_OBSERVATION")
                guard let press = active[ObservationKey(prefix: .press, token: token)],
                      profile == .keyboard else { throw HWPReject("REPEAT_WITHOUT_PRESS") }
                try need(press.source == source, "EPISODE_CHANGED")
            } else if kind.isUpdate {
                try need(focused && !suspended, "INPUT_OUTSIDE_OBSERVATION")
                guard let startKind = kind.matchingUpdateStart else {
                    throw HWPReject("OBSERVATION_KIND")
                }
                guard let begin = active[ObservationKey(prefix: startKind, token: token)] else {
                    throw HWPReject("UPDATE_WITHOUT_START")
                }
                try need(begin.source == source && begin.profile == profile, "EPISODE_CHANGED")
            }

            try need(fields[AlgorithmText("basis")] == nil || kind == .imeCommit,
                     "UNEXPECTED_BASIS")
            let hasEffect = fields[AlgorithmText("effect")] != nil
            try need(hasEffect == (kind == .delivery), "DELIVERY_FIELDS")
            var effect: HWPValue?
            if kind == .delivery {
                guard let raw = fields[AlgorithmText("effect")], case .map = raw else {
                    throw HWPReject("DELIVERY_EFFECT")
                }
                effect = raw
            }

            parsed.append(AlgorithmObservation(
                index: index, time: time, sequence: sequence, kind: kind, token: token,
                source: source, profile: profile, basis: basis, effect: effect))
        }
        try need(active.isEmpty, "UNCLOSED_INPUT")
        return (parsed, gap)
    }

    // MARK: Frozen `replay_document`

    struct PathEntry {
        let profile: HWPProfile
        let value: HWPValue
    }

    /// Frozen `INPUT_PATHS`: a non-empty map whose keys are profile names.
    /// Duplicate keys resolve last-wins in first-seen order, as a Python dict.
    static func pathMap(_ value: HWPValue?) throws -> [PathEntry] {
        guard case .map(let entries) = value, !entries.isEmpty else {
            throw HWPReject("INPUT_PATHS")
        }
        var result: [PathEntry] = []
        for entry in entries {
            guard case .text(let bytes) = entry.key,
                  let name = String(data: bytes, encoding: .utf8),
                  let profile = HWPProfile(rawValue: name) else { throw HWPReject("INPUT_PATHS") }
            if let existing = result.firstIndex(where: { $0.profile == profile }) {
                result[existing] = PathEntry(profile: profile, value: entry.value)
            } else {
                result.append(PathEntry(profile: profile, value: entry.value))
            }
        }
        return result
    }

    static func replayDocument(_ value: HWPValue, into corpus: AlgorithmCorpus) throws {
        try shape(value, required: documentFields)
        let fields = try map(value)

        let did = try string(try requireField(fields, "id"), maximum: 64)
        let didScalars = did.scalars
        try need(!did.isEmpty
                 && !didScalars.contains(0x3A)   // ':'
                 && !didScalars.contains(0x2F)   // '/'
                 && corpus.documents[did] == nil, "DOCUMENT_ID")

        let language = try string(try requireField(fields, "language"), maximum: 40)
        let languageScalars = language.scalars
        try need(!language.isEmpty
                 && !languageScalars.contains(0x7C)   // '|'
                 && !languageScalars.contains(0x2F)   // '/'
                 && !languageScalars.contains(0x5C), "LANGUAGE_DOMAIN")

        let pathEntries = try pathMap(try requireField(fields, "paths"))
        var paths: [HWPProfile: AlgorithmText] = [:]
        var pathOrder: [HWPProfile] = []
        paths.reserveCapacity(pathEntries.count)
        pathOrder.reserveCapacity(pathEntries.count)
        for entry in pathEntries {
            let path = try string(entry.value, maximum: 128)
            try need(!path.isEmpty && !path.scalars.contains(0x7C), "INPUT_PATH_ID")
            paths[entry.profile] = path
            pathOrder.append(entry.profile)
        }

        let resolution = try num(try requireField(fields, "resolution_us"), low: 1, high: 10_000)
        let (observations, gap) = try parseObservations(
            try requireField(fields, "observations"), resolution: resolution)
        let transactions = try HWPAlgorithmValues.array(
            try requireField(fields, "transactions"), reason: "TRANSACTION_LIMIT")
        try need(Int64(transactions.count) <= maxEvents, "TRANSACTION_LIMIT")

        // Frozen `timeline = sorted(obs + txs, key=num(seq))`. Python's sort is
        // stable, so ties keep observation-then-transaction arrival order.
        var timeline: [(sequence: Int64, time: HWPValue)] = []
        timeline.reserveCapacity(observations.count + transactions.count)
        for observation in observations {
            timeline.append((observation.sequence, .integer(observation.time)))
        }
        for transaction in transactions {
            guard case .map = transaction else { throw HWPReject("OPERATION") }
            timeline.append((try num(rawField(transaction, "seq")),
                             rawField(transaction, "t") ?? .null))
        }
        timeline = timeline.enumerated().sorted { left, right in
            left.element.sequence == right.element.sequence
                ? left.offset < right.offset
                : left.element.sequence < right.element.sequence
        }.map(\.element)

        for (index, entry) in timeline.enumerated() {
            try need(entry.sequence == Int64(index), "GLOBAL_SEQUENCE")
        }
        var previousTime: PyInt?
        for entry in timeline {
            guard let current = pythonInt(entry.time) else { throw HWPReject("GLOBAL_CLOCK") }
            if let previousTime { try need(!(current < previousTime), "GLOBAL_CLOCK") }
            previousTime = current
        }
        if observations.count > 1 {
            for index in 1..<observations.count {
                try need(observations[index - 1].sequence < observations[index].sequence,
                         "STREAM_ORDER")
            }
        }
        if transactions.count > 1 {
            for index in 1..<transactions.count {
                let previous = try num(rawField(transactions[index - 1], "seq"))
                let current = try num(rawField(transactions[index], "seq"))
                try need(previous < current, "STREAM_ORDER")
            }
        }
        for observation in observations {
            try need(paths[observation.profile] != nil, "UNDECLARED_INPUT_PATH")
        }

        var prefixBarriers: [Int64] = []
        prefixBarriers.reserveCapacity(observations.count)
        var barrierCount: Int64 = 0
        for observation in observations {
            if observation.kind.isBarrier { barrierCount += 1 }
            prefixBarriers.append(barrierCount)
        }

        var live: [AlgorithmText] = []
        var effects: [AlgorithmEffect] = []
        var undoStack: [HistoryDelta] = []
        var redoStack: [HistoryDelta] = []
        var unsafeControl = false
        var runAtoms: [AlgorithmText: [AlgorithmText]] = [:]
        var runOrder: [AlgorithmText] = []
        var consumed: Set<Int64> = []
        var lastTime: Int64 = 0
        var lastPosition: Int64 = 0
        var runNumber: Int64 = 0
        var cursor = 0
        var pendingNavigation: Int64 = 0
        var lastProfile: HWPProfile?
        var lastSource: HWPTextSource?
        var focused = true
        var suspended = false
        var pendingBarrier = false

        for (position, transaction) in transactions.enumerated() {
            try Task.checkCancellation()

            // Frozen `OPERATION`: a map with a known string `op`.
            guard case .map = transaction,
                  let opValue = rawField(transaction, "op"),
                  case .text(let opBytes) = opValue,
                  let opName = String(data: opBytes, encoding: .utf8),
                  let op = HWPOp(rawValue: opName) else { throw HWPReject("OPERATION") }
            try shape(transaction, required: transactionCommonFields.union(op.specificFields))
            let tx = try map(transaction)
            try need(try num(try requireField(tx, "i")) == Int64(position), "TRANSACTION_SEQUENCE")
            let time = try num(try requireField(tx, "t"))
            try need(time >= lastTime && time % resolution == 0, "TRANSACTION_CLOCK")
            let profile = try enumValue(try requireField(tx, "profile"), HWPProfile.self,
                                        reason: "PROFILE")
            let sequence = try num(try requireField(tx, "seq"))

            while cursor < observations.count, observations[cursor].sequence < sequence {
                let observation = observations[cursor]
                if observation.kind.isBarrier { pendingBarrier = true }
                switch observation.kind {
                case .focusOut: focused = false
                case .focusIn: focused = true
                case .suspend: suspended = true
                case .resume: suspended = false
                default: break
                }
                cursor += 1
            }

            let delivery = try num(try requireField(tx, "delivery"), low: 0,
                                   high: Int64(observations.count) - 1)
            let delivered = observations[Int(delivery)]
            try need(delivered.kind == .delivery
                     && delivered.sequence < sequence
                     && !consumed.contains(delivery), "DELIVERY_BINDING")
            try need(delivered.profile == profile
                     && time - delivered.time >= 0
                     && time - delivered.time <= maxCauseDelay, "DELIVERY_DELAY_OR_PROFILE")

            // Frozen `DELIVERY_EFFECT_MISMATCH`: canonical JSON equality of the
            // delivered effect and the transaction's own fields, minus identity
            // and clock fields. `HWPValue` equality is map-order independent and
            // keeps booleans distinct from integers, matching `sort_keys`.
            var contract: [HWPEntry] = []
            for entry in try map(transaction) {
                guard !deliveryContractExcluded.contains(entry.key.string) else { continue }
                contract.append(HWPEntry(entry.key.value, entry.value))
            }
            guard let effectValue = delivered.effect else { throw HWPReject("DELIVERY_EFFECT") }
            try need(effectValue == .map(contract), "DELIVERY_EFFECT_MISMATCH")
            consumed.insert(delivery)

            let causeValues = try integerList(tx[AlgorithmText("causes")], typeReason: "CAUSES",
                                              duplicateReason: "CAUSE_REUSE", maximum: maxCauses)
            var causes: [Int64] = []
            causes.reserveCapacity(causeValues.count)
            for element in causeValues {
                let cause = try HWPAlgorithmValues.integer(
                    element, low: 0, high: Int64(observations.count) - 1)
                let observation = observations[Int(cause)]
                try need(observation.sequence < delivered.sequence
                         && observation.time <= time
                         && !consumed.contains(cause), "CAUSE_REUSE_OR_FUTURE")
                try need(observation.profile == profile
                         && causeKinds.contains(observation.kind), "CAUSE_PROFILE")
                consumed.insert(cause)
                for basis in observation.basis ?? [] {
                    try need(!consumed.contains(basis), "IME_DOUBLE_SPEND")
                    consumed.insert(basis)
                }
                causes.append(cause)
            }

            try need(focused && !suspended, "TRANSACTION_OUTSIDE_OBSERVATION")
            for cause in causes {
                try need(time - observations[Int(cause)].time <= maxCauseDelay,
                         "DELAYED_INPUT_BINDING")
            }
            for cause in causes {
                try need(prefixBarriers[Int(cause)] == prefixBarriers[Int(delivery)],
                         "CAUSE_CROSSES_INTERRUPTION")
            }
            let nonDevice = delivered.source != .device
                || causes.contains { observations[Int($0)].source != .device }
            if op != .splice && nonDevice { unsafeControl = true }

            let source = try enumValue(
                rawField(transaction, "source") ?? .text(Data("control".utf8)),
                HWPTextSource.self, reason: "TEXT_SOURCE")
            try need(HWPTextSource.allowed(for: op).contains(source), "TEXT_SOURCE")

            let beforeLength = Int64(live.count)
            var start: Int64
            var end: Int64
            if op == .splice || op == .move || op == .navigate {
                start = try num(try requireField(tx, "start"), low: 0, high: Int64(live.count))
                end = try num(try requireField(tx, "end"), low: start, high: Int64(live.count))
            } else {
                start = min(lastPosition, Int64(live.count))
                end = start
            }

            var barrier = pendingBarrier
                || time - lastTime > runGap
                || lastProfile != profile
                || abs(start - lastPosition) > 256
            barrier = barrier
                || !(source == .direct || source == .spelling || source == .control)
                || !(lastSource == nil || lastSource == .direct
                     || lastSource == .spelling || lastSource == .control)
            if barrier { runNumber += 1 }
            let run = try joined([did.utf8, Data(":run:\(runNumber)".utf8)])
            if runAtoms[run] == nil { runAtoms[run] = []; runOrder.append(run) }

            var old = AlgorithmText("")
            var new = AlgorithmText("")
            var born: [AlgorithmText] = []
            var touched: Set<AlgorithmText> = []
            var delta: HistoryDelta?
            let precedingScalar: UInt32
            if start > 0 {
                guard let atom = corpus.atoms[live[Int(start - 1)]] else {
                    throw HWPReject("UNKNOWN_ATOM")
                }
                precedingScalar = atom.char.scalars.first ?? 0x000A
            } else {
                precedingScalar = 0x000A
            }
            let preceding: Int64
            if lineBreakScalars.contains(precedingScalar) { preceding = 3 }
            else if stopScalars.contains(precedingScalar) { preceding = 2 }
            else if spaceScalars.contains(precedingScalar) { preceding = 1 }
            else { preceding = 0 }

            var effectiveSource = source

            if op == .navigate {
                pendingNavigation += abs(start - lastPosition)
                lastPosition = start
            } else if op == .splice {
                old = try string(try requireField(tx, "deleted"))
                new = try string(try requireField(tx, "text"))
                let removed = Array(live[Int(start)..<Int(end)])
                if !removed.isEmpty && nonDevice { unsafeControl = true }
                try need(try corpus.text(removed) == old && !(old.isEmpty && new.isEmpty),
                         "MUTATION_PRESTATE")
                for atom in removed {
                    guard let record = corpus.atoms[atom] else { throw HWPReject("UNKNOWN_ATOM") }
                    touched.formUnion(record.roots)
                }
                var candidate = source == .direct
                if candidate {
                    try need(causes.allSatisfy {
                        prefixBarriers[Int($0)] == prefixBarriers[Int(delivery)]
                    }, "CAUSE_CROSSES_INTERRUPTION")
                    try need(focused && !suspended, "MUTATION_OUTSIDE_OBSERVATION")
                    try need(causes.allSatisfy {
                        time - observations[Int($0)].time <= maxCauseDelay
                    }, "DELAYED_INPUT_BINDING")
                    try need(causes.allSatisfy {
                        profile.allowsDirectCause(observations[Int($0)].kind)
                    }, "DIRECT_CAUSE")
                    try need(Int64(new.count)
                             <= profile.maximumDirectInsertionPerCause * Int64(causes.count),
                             "BULK_DIRECT_INSERTION")
                    if nonDevice {
                        candidate = false
                        effectiveSource = .unknown
                    }
                }
                try need(Int64(live.count) - (end - start) + Int64(new.count) <= maxScalars
                         && Int64(corpus.atoms.count) + Int64(new.count) <= maxAtoms,
                         "REPLAY_RESOURCE_LIMIT")
                var inserted: [AlgorithmText] = []
                inserted.reserveCapacity(new.scalars.count)
                for (offset, scalar) in new.scalars.enumerated() {
                    if offset % 1024 == 0 { try Task.checkCancellation() }
                    let aid = try atomID(did, Int64(position), Int64(offset))
                    try need(corpus.atoms[aid] == nil, "ATOM_COLLISION")
                    let char = try AlgorithmText(scalars: [scalar])
                    if candidate {
                        corpus.addAtom(AlgorithmAtom(
                            aid: aid, char: char, roots: [aid], kind: .candidate, home: did,
                            birth: Int64(position), run: run, profile: profile,
                            requirements: [did], spelling: false))
                        born.append(aid)
                        runAtoms[run]?.append(aid)
                    } else {
                        // Frozen spelling/paste/generated/unknown reuse never
                        // inherits roots: these atoms are external evidence.
                        corpus.addAtom(AlgorithmAtom(
                            aid: aid, char: char, roots: [], kind: .external, home: did,
                            birth: Int64(position), run: run, profile: profile,
                            requirements: [did], spelling: false))
                    }
                    inserted.append(aid)
                }
                if effectiveSource != .direct && !new.isEmpty {
                    corpus.chargeExternalScalars(Int64(new.count))
                    try need(corpus.externalScalars <= maxExternalScalars, "SOURCE_INDEX_LIMIT")
                    corpus.addExternal(AlgorithmExternal(owner: did,
                                                         transaction: Int64(position), text: new))
                }
                live.replaceSubrange(Int(start)..<Int(end), with: inserted)
                delta = HistoryDelta(position: start, removed: removed, inserted: inserted,
                                     origin: Int64(position))
                touched.formUnion(born)
                lastPosition = start + Int64(new.count)
            } else if op == .copy {
                guard let parentValue = tx[AlgorithmText("from_doc")],
                      case .text(let parentBytes) = parentValue,
                      let parent = try? AlgorithmText(utf8: parentBytes),
                      parent == did || corpus.documents[parent] != nil else {
                    throw HWPReject("PARENT_UNAVAILABLE")
                }
                let sourceLive = parent == did ? live : (corpus.documents[parent]?.live ?? [])
                let s = try num(try requireField(tx, "start"), low: 0,
                                high: Int64(sourceLive.count))
                let e = try num(try requireField(tx, "end"), low: s + 1,
                                high: Int64(sourceLive.count))
                let to = try num(try requireField(tx, "to"), low: 0, high: Int64(live.count))
                start = to
                try need(Int64(live.count) + e - s <= maxScalars
                         && Int64(corpus.atoms.count) + e - s <= maxAtoms,
                         "REPLAY_RESOURCE_LIMIT")
                var inserted: [AlgorithmText] = []
                inserted.reserveCapacity(Int(e - s))
                for (offset, original) in sourceLive[Int(s)..<Int(e)].enumerated() {
                    if offset % 1024 == 0 { try Task.checkCancellation() }
                    guard let record = corpus.atoms[original] else {
                        throw HWPReject("UNKNOWN_ATOM")
                    }
                    let aid = try atomID(did, Int64(position), Int64(offset))
                    try need(corpus.atoms[aid] == nil, "ATOM_COLLISION")
                    corpus.addAtom(AlgorithmAtom(
                        aid: aid, char: record.char, roots: record.roots, kind: record.kind,
                        home: record.home, birth: record.birth, run: record.run,
                        profile: record.profile, requirements: record.requirements.union([did]),
                        spelling: record.spelling))
                    inserted.append(aid)
                    touched.formUnion(record.roots)
                }
                live.insert(contentsOf: inserted, at: Int(to))
                new = try corpus.text(inserted)
                delta = HistoryDelta(position: to, removed: [], inserted: inserted,
                                     origin: Int64(position))
                lastPosition = to + Int64(inserted.count)
            } else if op == .move {
                try need(start < end, "EMPTY_MOVE")
                let to = try num(try requireField(tx, "to"), low: 0,
                                 high: Int64(live.count) - (end - start))
                let lo = min(start, to)
                let hi = max(end, to + end - start)
                let before = Array(live[Int(lo)..<Int(hi)])
                let moved = Array(live[Int(start)..<Int(end)])
                live.removeSubrange(Int(start)..<Int(end))
                live.insert(contentsOf: moved, at: Int(to))
                delta = HistoryDelta(position: lo, removed: before,
                                     inserted: Array(live[Int(lo)..<Int(hi)]),
                                     origin: Int64(position))
                for atom in moved {
                    guard let record = corpus.atoms[atom] else { throw HWPReject("UNKNOWN_ATOM") }
                    touched.formUnion(record.roots)
                }
                old = try corpus.text(moved)
                new = old
                lastPosition = to + Int64(moved.count)
            } else {
                let ref = try num(try requireField(tx, "ref"), low: 0,
                                  high: Int64(position) - 1)
                let isUndo = op == .undo
                let top = isUndo ? undoStack.last : redoStack.last
                try need(top != nil && top?.origin == ref, "HISTORY_TARGET")
                let popped = isUndo ? undoStack.removeLast() : redoStack.removeLast()
                let expected = isUndo ? popped.inserted : popped.removed
                let restore = isUndo ? popped.removed : popped.inserted
                let from = min(popped.position, Int64(live.count))
                let through = min(popped.position + Int64(expected.count), Int64(live.count))
                try need(Array(live[Int(from)..<Int(through)]) == expected, "HISTORY_PRESTATE")
                live.replaceSubrange(Int(from)..<Int(through), with: restore)
                if isUndo { redoStack.append(popped) } else { undoStack.append(popped) }
                start = popped.position
                old = try corpus.text(expected)
                new = try corpus.text(restore)
                for aid in Set(popped.removed).union(popped.inserted) {
                    guard let atom = corpus.atoms[aid] else { throw HWPReject("UNKNOWN_ATOM") }
                    touched.formUnion(atom.roots)
                }
                lastPosition = popped.position + Int64(restore.count)
            }

            if let delta {
                undoStack.append(delta)
                redoStack.removeAll()
                corpus.chargeStoredIDs(Int64(delta.removed.count)
                                       + Int64(delta.inserted.count))
            }
            try need(Int64(live.count) <= maxScalars
                     && Int64(corpus.atoms.count) <= maxAtoms
                     && corpus.storedIDs <= maxIDsStored, "REPLAY_RESOURCE_LIMIT")

            var ages: [Int64] = []
            ages.reserveCapacity(touched.count)
            for root in touched {
                guard let record = corpus.atoms[root] else { throw HWPReject("UNKNOWN_ATOM") }
                if record.home == did { ages.append(Int64(position) - record.birth) }
            }
            ages.sort()
            effects.append(AlgorithmEffect(
                index: Int64(position), time: time, op: op, source: effectiveSource,
                profile: profile, run: run, pos: start, beforeLength: beforeLength,
                old: old, new: new, born: born, touched: touched, causes: causes,
                preceding: preceding, navigation: pendingNavigation, ages: ages,
                barrier: barrier))
            corpus.chargeEffectEdges(Int64(touched.count))
            try need(corpus.effectEdges <= maxEffectEdges, "EVIDENCE_EDGE_LIMIT")
            for root in touched {
                corpus.addRootEffect(root, document: did, index: Int64(position))
            }
            lastTime = time
            lastProfile = profile
            lastSource = effectiveSource
            if op != .navigate { pendingNavigation = 0 }
            pendingBarrier = false
        }

        // Fresh atom ids and stack-checked operations preserve uniqueness
        // inductively; check the final invariant without quadratic rescans.
        try need(live.count == Set(live).count, "DUPLICATE_LIVE_ID")
        let final = try string(try requireField(fields, "final_text"))
        try need(try corpus.text(live) == final, "FINAL_TEXT_MISMATCH")
        for observation in observations where observation.kind == .delivery {
            try need(consumed.contains(observation.index), "UNACCOUNTED_DELIVERY")
        }

        var starts: [ObservationKey: AlgorithmObservation] = [:]
        var durations: [AlgorithmDuration] = []
        var durationSlots: [Int64: Int] = [:]
        func setDuration(_ index: Int64, _ duration: Int64) {
            if let slot = durationSlots[index] {
                durations[slot] = AlgorithmDuration(index: index, duration: duration)
            } else {
                durationSlots[index] = durations.count
                durations.append(AlgorithmDuration(index: index, duration: duration))
            }
        }
        for observation in observations {
            switch observation.kind {
            case .press, .touchDown, .gestureStart:
                starts[ObservationKey(prefix: observation.kind, token: observation.token)] =
                    observation
            case .release, .touchUp, .gestureEnd:
                guard let startKind = observation.kind.matchingStart,
                      let begin = starts[ObservationKey(prefix: startKind,
                                                        token: observation.token)] else {
                    throw HWPReject("DURATION_START_MISSING")
                }
                setDuration(begin.index, observation.time - begin.time)
                if observation.kind == .gestureEnd {
                    setDuration(observation.index, observation.time - begin.time)
                }
            default:
                break
            }
        }

        corpus.addDocument(AlgorithmDocument(
            did: did, language: language, resolution: resolution, observations: observations,
            effects: effects, live: live, text: final, gap: gap,
            runs: runOrder.map { AlgorithmRun(run: $0, atoms: runAtoms[$0] ?? []) },
            paths: paths, pathOrder: pathOrder, durations: durations,
            unsafeControl: unsafeControl))
    }
}
