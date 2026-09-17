import Foundation
import WriterFoundation

/// Bounded private-evidence transport, ported from frozen `hwp0/disclosure.py`.
///
/// This object is a transport for openings, never a proof. The protocol root
/// commitments, not this transport, authenticate the evidence. Chunking avoids an
/// artificial one-CBOR-object limit on long observed histories.
public enum HWPDisclosure {
    public static let block = 256
    public static let maximumLogs = 4096
    public static let maximumLineageSalts = 64

    /// Canonical transport bundle for `{'logs': …, 'lineage_salts': …}`.
    public static func pack(_ value: HWPValue) throws -> Data {
        try value.requireFields(["logs", "lineage_salts"])
        guard case .array(let rawLogs) = value.field("logs")!, rawLogs.count <= maximumLogs else {
            throw HWPReject("disclosure-count")
        }
        guard case .array(let rawSalts) = value.field("lineage_salts")!, rawSalts.count <= maximumLineageSalts else {
            throw HWPReject("disclosure-count")
        }

        var store = HWPObjectStore()
        var logEntries: [(key: Data, value: HWPValue)] = []
        var seenCaptures = Set<Data>()
        var eventCount = 0
        var totalBytes = 0
        for rawLog in rawLogs {
            try Task.checkCancellation()
            try rawLog.requireFields(["capture", "openings"])
            let capture = rawLog.field("capture")!
            let captureKey = try referenceDigest(capture)
            guard seenCaptures.insert(captureKey).inserted else {
                throw HWPReject("duplicate-disclosed-session")
            }
            guard case .array(let openings) = rawLog.field("openings")! else {
                throw HWPReject("disclosure-openings")
            }
            for (index, opening) in openings.enumerated() {
                try Task.checkCancellation()
                try opening.requireFields(["index", "salt", "event"])
                guard let position = smallInteger(opening.field("index")!), position == Int64(index) else {
                    throw HWPReject("opening-order")
                }
                guard case .bytes(let eventBytes) = opening.field("event")! else {
                    throw HWPReject("byte-string-domain")
                }
                guard eventBytes.count <= HWPCBOR.maximumBytes else { throw HWPReject("byte-string-domain") }
                guard case .bytes(let salt) = opening.field("salt")! else {
                    throw HWPReject("byte-string-domain")
                }
                guard salt.count == 32 else { throw HWPReject("byte-string-length") }
                totalBytes += eventBytes.count + 32
                eventCount += 1
                guard totalBytes <= HWPCBOR.maximumBytes, eventCount <= HWPMerkle.maximumEvents else {
                    throw HWPReject("disclosure-budget")
                }
                _ = try HWPCBOR.decode(eventBytes)
            }
            var parts: [HWPValue] = []
            for offset in stride(from: 0, to: openings.count, by: block) {
                let slice = Array(openings[offset..<min(offset + block, openings.count)])
                let rawBlock = try HWPCBOR.encode(.map([
                    HWPEntry(.text("v"), .text("hwp/0")),
                    HWPEntry(.text("type"), .text("opening-block")),
                    HWPEntry(.text("offset"), .unsigned(UInt64(offset))),
                    HWPEntry(.text("openings"), .array(slice)),
                ]))
                _ = try HWPCBOR.decode(rawBlock)
                parts.append(try store.add(rawBlock).value)
            }
            logEntries.append((captureKey, .map([
                HWPEntry(.text("capture"), capture),
                HWPEntry(.text("count"), .unsigned(UInt64(openings.count))),
                HWPEntry(.text("parts"), .array(parts)),
            ])))
        }
        logEntries.sort { $0.key.lexicographicallyPrecedes($1.key) }

        var saltEntries: [(key: Data, value: HWPValue)] = []
        var seenStatements = Set<Data>()
        for rawSalt in rawSalts {
            try Task.checkCancellation()
            try rawSalt.requireFields(["statement", "salt"])
            let statement = rawSalt.field("statement")!
            let statementKey = try referenceDigest(statement)
            guard case .bytes(let salt) = rawSalt.field("salt")!, salt.count <= HWPCBOR.maximumBytes else {
                throw HWPReject("byte-string-domain")
            }
            guard salt.count == 32 else { throw HWPReject("byte-string-length") }
            guard seenStatements.insert(statementKey).inserted else {
                throw HWPReject("duplicate-lineage-salt")
            }
            saltEntries.append((statementKey, rawSalt))
        }
        saltEntries.sort { $0.key.lexicographicallyPrecedes($1.key) }

        let root = try store.put(.map([
            HWPEntry(.text("v"), .text("hwp/0")),
            HWPEntry(.text("type"), .text("private-disclosure")),
            HWPEntry(.text("logs"), .array(logEntries.map(\.value))),
            HWPEntry(.text("lineage_salts"), .array(saltEntries.map(\.value))),
        ]))
        return try store.pack(root: root)
    }

    /// Exact inverse of `pack` for canonical bundles; rejects anything it cannot repack.
    public static func unpack(_ raw: Data) throws -> HWPValue {
        let (store, root) = try HWPObjectStore.unpack(raw)
        let manifest = try store.object(root)
        try manifest.requireType("private-disclosure", fields: ["logs", "lineage_salts"])
        guard case .array(let rawLogs) = manifest.field("logs")!, rawLogs.count <= maximumLogs else {
            throw HWPReject("disclosure-count")
        }
        var logs: [HWPValue] = []
        var previous: Data?
        var used = Set<Data>([root.sha256])
        // Cheap pre-pass: sum the declared counts before dereferencing any block, so a
        // small bundle cannot reference one block from many captures and amplify work.
        // Malformed logs are skipped here and rejected with their own reason below.
        var declaredTotal = 0
        for rawLog in rawLogs {
            guard case .map(let entries) = rawLog,
                  case .unsigned(let declared) = entries.first(where: { $0.key == .text("count") })?.value,
                  declared <= UInt64(HWPMerkle.maximumEvents) else { continue }
            declaredTotal += Int(declared)
        }
        guard declaredTotal <= HWPMerkle.maximumEvents else { throw HWPReject("disclosure-budget") }
        var declaredEvents = 0
        var decodedBytes = 0
        // Object keys are not public on the store; every reachable digest is tracked in
        // `used`, so an equal object count proves `used == objects` (no unrelated object).
        for rawLog in rawLogs {
            try Task.checkCancellation()
            try rawLog.requireFields(["capture", "count", "parts"])
            let capture = rawLog.field("capture")!
            let key = try referenceDigest(capture)
            guard previous == nil || previous!.lexicographicallyPrecedes(key) else {
                throw HWPReject("disclosure-order")
            }
            previous = key
            let count = try boundedInteger(rawLog.field("count")!, 0, Int64(HWPMerkle.maximumEvents))
            // Bound the declared history before any block is dereferenced: repeated
            // block references across many captures must not amplify allocation.
            declaredEvents += Int(count)
            guard declaredEvents <= HWPMerkle.maximumEvents else { throw HWPReject("disclosure-budget") }
            guard case .array(let parts) = rawLog.field("parts")! else { throw HWPReject("opening-block-count") }
            let expected = (count + Int64(block) - 1) / Int64(block)
            guard Int64(parts.count) == expected else { throw HWPReject("opening-block-count") }
            var openings: [HWPValue] = []
            for (index, part) in parts.enumerated() {
                try Task.checkCancellation()
                try validRef(part)
                let reference = try HWPReference(value: part)
                let rawBlock = try store.get(reference)
                let blockValue = try HWPCBOR.decode(rawBlock)
                used.insert(reference.sha256)
                try blockValue.requireType("opening-block", fields: ["offset", "openings"])
                guard let offset = smallInteger(blockValue.field("offset")!),
                      offset == Int64(index * block) else { throw HWPReject("opening-block-offset") }
                guard case .array(let chunk) = blockValue.field("openings")! else {
                    throw HWPReject("opening-block-size")
                }
                guard chunk.count == min(block, Int(count - Int64(index * block))) else {
                    throw HWPReject("opening-block-size")
                }
                // Charge the frozen event+salt budget as each chunk is consumed; an
                // ill-formed chunk is charged its whole encoded size instead.
                var charge = 0
                var wellFormed = true
                for opening in chunk {
                    guard case .bytes(let event)? = opening.field("event"),
                          case .bytes? = opening.field("salt") else {
                        wellFormed = false
                        break
                    }
                    charge += event.count + 32
                }
                decodedBytes += wellFormed ? charge : rawBlock.count
                guard decodedBytes <= HWPCBOR.maximumBytes else { throw HWPReject("disclosure-budget") }
                openings.append(contentsOf: chunk)
            }
            logs.append(.map([
                HWPEntry(.text("capture"), capture),
                HWPEntry(.text("openings"), .array(openings)),
            ]))
        }
        let value = HWPValue.map([
            HWPEntry(.text("logs"), .array(logs)),
            HWPEntry(.text("lineage_salts"), manifest.field("lineage_salts")!),
        ])
        guard used.count == store.count else { throw HWPReject("unrelated-private-object") }
        // Repacking validates budgets, unique references, event CBOR, salt sizes and order.
        guard try pack(value) == raw else { throw HWPReject("private-disclosure-noncanonical") }
        return value
    }

    // MARK: - Frozen field domains

    private static func referenceDigest(_ value: HWPValue) throws -> Data {
        try validRef(value)
        guard case .bytes(let digest) = value.field("sha256")! else { throw HWPReject("byte-string-domain") }
        return digest
    }

    private static func validRef(_ value: HWPValue) throws {
        try value.requireFields(["sha256", "size"])
        guard case .bytes(let digest) = value.field("sha256")! else { throw HWPReject("byte-string-domain") }
        guard digest.count == 32 else { throw HWPReject("byte-string-length") }
        _ = try boundedInteger(value.field("size")!, 0, Int64(HWPCBOR.maximumBytes))
    }

    private static func smallInteger(_ value: HWPValue) -> Int64? {
        switch value {
        case .unsigned(let number): return number <= UInt64(Int64.max) ? Int64(number) : nil
        case .negative(let number): return number
        default: return nil
        }
    }

    private static func boundedInteger(_ value: HWPValue, _ low: Int64, _ high: Int64) throws -> Int64 {
        guard let number = smallInteger(value), low <= number, number <= high else {
            throw HWPReject("integer-domain")
        }
        return number
    }
}
