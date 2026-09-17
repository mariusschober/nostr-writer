import Foundation
import Security
import WriterFoundation

/// Observed-history commitments and their complete openings, ported from frozen
/// `core.py` `commit_events` / `open_transcript`.
public enum HWPTranscript {
    /// Commit `events` under `start`. Salts default to fresh CSPRNG bytes.
    public static func commit(start: HWPReference, events: [HWPValue], salts: [Data]? = nil) throws
        -> (root: Data, openings: [HWPValue])
    {
        guard (2...HWPMerkle.maximumEvents).contains(events.count) else { throw HWPReject("event-count") }
        let chosen: [Data]
        if let salts {
            guard salts.count == events.count, Set(salts).count == salts.count else {
                throw HWPReject("salt-count-or-reuse")
            }
            chosen = salts
        } else {
            // Fresh salts come from the platform CSPRNG and must never repeat; generation
            // is cancellable and bounded so a degenerate source cannot spin forever.
            var generated = Set<Data>()
            var fresh: [Data] = []
            fresh.reserveCapacity(events.count)
            for _ in 0..<events.count {
                try Task.checkCancellation()
                var candidate = try random32()
                var attempts = 0
                while generated.contains(candidate) {
                    attempts += 1
                    guard attempts <= 8 else { throw HWPReject("random-source-failure") }
                    try Task.checkCancellation()
                    candidate = try random32()
                }
                generated.insert(candidate)
                fresh.append(candidate)
            }
            chosen = fresh
        }
        var leaves: [Data] = []
        var openings: [HWPValue] = []
        leaves.reserveCapacity(events.count)
        openings.reserveCapacity(events.count)
        var budget = 0
        for index in 0..<events.count {
            try Task.checkCancellation()
            let eventBytes = try HWPCBOR.encode(events[index])
            // Native bound consistent with the admissible disclosure budget: refuse to
            // retain a history larger than the transport could ever disclose.
            budget += eventBytes.count + 32
            guard budget <= HWPCBOR.maximumBytes else { throw HWPReject("disclosure-budget") }
            let salt = chosen[index]
            leaves.append(try HWPMerkle.leaf(startDigest: start.sha256, index: index, salt: salt, event: eventBytes))
            openings.append(.map([
                HWPEntry(.text("index"), .unsigned(UInt64(index))),
                HWPEntry(.text("salt"), .bytes(salt)),
                HWPEntry(.text("event"), .bytes(eventBytes)),
            ]))
        }
        return (try HWPMerkle.root(leaves), openings)
    }

    /// Open a complete transcript: every index, no reused salt, terminal header/end.
    public static func open(start: HWPReference, count: Int, root: Data, openings: [HWPValue]) throws
        -> [HWPValue]
    {
        guard count >= 2, count <= HWPMerkle.maximumEvents else { throw HWPReject("integer-domain") }
        guard openings.count == count else { throw HWPReject("complete-disclosure-required") }
        var leaves: [Data] = []
        var events: [HWPValue] = []
        var salts = Set<Data>()
        leaves.reserveCapacity(count)
        events.reserveCapacity(count)
        var budget = 0
        for (index, opening) in openings.enumerated() {
            try Task.checkCancellation()
            try opening.requireFields(["index", "salt", "event"])
            guard let position = smallInteger(opening.field("index")!), position == Int64(index) else {
                throw HWPReject("opening-order")
            }
            guard case .bytes(let salt) = opening.field("salt")! else { throw HWPReject("byte-string-domain") }
            guard salt.count <= HWPCBOR.maximumBytes else { throw HWPReject("byte-string-domain") }
            guard salt.count == 32 else { throw HWPReject("byte-string-length") }
            guard salts.insert(salt).inserted else { throw HWPReject("salt-reuse") }
            guard case .bytes(let eventBytes) = opening.field("event")! else {
                throw HWPReject("byte-string-domain")
            }
            // Budget before decoding: a complete transcript may not exceed the same
            // aggregate event+salt ceiling the disclosure transport enforces.
            budget += eventBytes.count + 32
            guard budget <= HWPCBOR.maximumBytes else { throw HWPReject("disclosure-budget") }
            leaves.append(try HWPMerkle.leaf(startDigest: start.sha256, index: index, salt: salt, event: eventBytes))
            events.append(try HWPCBOR.decode(eventBytes))
        }
        let computed = try HWPMerkle.root(leaves)
        guard root.count == 32 else { throw HWPReject("byte-string-length") }
        guard computed == root else { throw HWPReject("transcript-root") }
        guard events[0].field("kind") == .text("header") else { throw HWPReject("transcript-header") }
        guard events[events.count - 1].field("kind") == .text("end") else {
            throw HWPReject("transcript-terminal")
        }
        return events
    }

    // MARK: - Helpers

    private static func smallInteger(_ value: HWPValue) -> Int64? {
        switch value {
        case .unsigned(let number): return number <= UInt64(Int64.max) ? Int64(number) : nil
        case .negative(let number): return number
        default: return nil
        }
    }

    /// Fresh salts come from the platform CSPRNG, never a seedable generator.
    private static func random32() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw HWPReject("random-source-failure")
        }
        return Data(bytes)
    }
}
