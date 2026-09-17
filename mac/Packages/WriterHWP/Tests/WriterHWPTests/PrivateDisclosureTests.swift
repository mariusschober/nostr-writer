import XCTest
import CryptoKit
@testable import WriterHWP

/// Frozen-oracle tests for the private disclosure transport and transcript openings.
///
/// Every expected byte in `disclosure-oracle.json` was produced by the frozen
/// `hwp0/disclosure.py` and `hwp0/core.py` implementations through
/// `Tools/generate_disclosure_oracles.py`. The `full` case is the frozen
/// interchange vector's own complete ladder disclosure (1250 openings, 5 blocks).
final class PrivateDisclosureTests: XCTestCase {

    // MARK: - Frozen fixture

    private struct Fixture: Decodable {
        struct Ref: Decodable { let sha256_hex: String; let size: Int }
        struct Opening: Decodable { let index: Int; let salt_hex: String; let event_hex: String }
        struct Salt: Decodable { let statement: Ref; let salt_hex: String }
        struct Log: Decodable { let capture: Ref; let openings: [Opening] }
        struct ABI: Decodable { let logs: [Log]; let lineage_salts: [Salt] }
        struct Case: Decodable {
            let value: ABI
            let input: ABI
            let pack_hex: String
            let opening_counts: [Int]
            let reordered_pack_hex: String?
        }
        struct Full: Decodable {
            let pack_hex: String
            let start: Ref
            let count: Int
            let root_hex: String
            let capture_hex: String
            let opening_counts: [Int]
            let blocks: Int
            let lineage_salts: Int
        }
        struct Transcript: Decodable {
            let start: Ref
            let events_hex: [String]
            let salts_hex: [String]
            let root_hex: String
            let openings: [Opening]
        }
        let source_sha256: [String: String]
        let small: Case
        let chunked: Case
        let capture: Case
        let salts: Case
        let full: Full
        let transcript: Transcript
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "disclosure-oracle", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
    }

    private var cases: [(String, (Fixture) -> Fixture.Case)] {
        [("small", \.small), ("chunked", \.chunked), ("capture", \.capture), ("salts", \.salts)]
    }

    // MARK: - Value plumbing

    private func data(_ hex: String) -> Data {
        var output = Data()
        output.reserveCapacity(hex.utf8.count / 2)
        var high: UInt8?
        for byte in hex.utf8 {
            let nibble: UInt8
            switch byte {
            case 0x30...0x39: nibble = byte - 0x30
            case 0x61...0x66: nibble = byte - 0x57
            case 0x41...0x46: nibble = byte - 0x37
            default: continue
            }
            if let existing = high { output.append((existing << 4) | nibble); high = nil } else { high = nibble }
        }
        return output
    }

    private func referenceValue(_ value: Fixture.Ref) -> HWPValue {
        .map([HWPEntry(.text("sha256"), .bytes(data(value.sha256_hex))),
              HWPEntry(.text("size"), .unsigned(UInt64(value.size)))])
    }

    private func openingValue(_ value: Fixture.Opening) -> HWPValue {
        .map([HWPEntry(.text("index"), .unsigned(UInt64(value.index))),
              HWPEntry(.text("salt"), .bytes(data(value.salt_hex))),
              HWPEntry(.text("event"), .bytes(data(value.event_hex)))])
    }

    private func abiValue(_ value: Fixture.ABI) -> HWPValue {
        .map([
            HWPEntry(.text("logs"), .array(value.logs.map { log in
                .map([HWPEntry(.text("capture"), referenceValue(log.capture)),
                      HWPEntry(.text("openings"), .array(log.openings.map(openingValue)))])
            })),
            HWPEntry(.text("lineage_salts"), .array(value.lineage_salts.map { salt in
                .map([HWPEntry(.text("statement"), referenceValue(salt.statement)),
                      HWPEntry(.text("salt"), .bytes(data(salt.salt_hex)))])
            })),
        ])
    }

    // MARK: - Transport shape helpers

    private func logs(_ value: HWPValue) throws -> [HWPValue] {
        guard case .array(let logs) = value.field("logs")! else { throw HWPReject("test-shape") }
        return logs
    }

    private func openings(_ log: HWPValue) throws -> [HWPValue] {
        guard case .array(let openings) = log.field("openings")! else { throw HWPReject("test-shape") }
        return openings
    }

    private func parts(_ log: HWPValue) throws -> [HWPValue] {
        guard case .array(let parts) = log.field("parts")! else { throw HWPReject("test-shape") }
        return parts
    }

    private func replacing(_ value: HWPValue, _ key: String, with replacement: HWPValue) throws -> HWPValue {
        guard case .map(let entries) = value else { throw HWPReject("test-shape") }
        var found = false
        let updated = entries.map { entry -> HWPEntry in
            guard entry.key == .text(key) else { return entry }
            found = true
            return HWPEntry(entry.key, replacement)
        }
        guard found else { throw HWPReject("test-shape") }
        return .map(updated)
    }

    /// Re-encode a bundle with a mutated manifest, carrying only referenced parts.
    private func rebuildingManifest(_ raw: Data,
                                    _ mutate: (HWPValue) throws -> HWPValue) throws -> Data {
        let (source, root) = try HWPObjectStore.unpack(raw)
        let manifest = try source.object(root)
        var store = HWPObjectStore()
        for log in try logs(manifest) {
            for part in try parts(log) { _ = try store.add(try source.get(HWPReference(value: part))) }
        }
        let newRoot = try store.put(try mutate(manifest))
        return try store.pack(root: newRoot)
    }

    /// Re-encode a bundle with the first log's first opening-block mutated.
    private func rebuildingFirstBlock(_ raw: Data,
                                      _ mutate: (HWPValue) throws -> HWPValue) throws -> Data {
        let (source, root) = try HWPObjectStore.unpack(raw)
        let manifest = try source.object(root)
        var allLogs = try logs(manifest)
        let existing = try parts(allLogs[0])
        var store = HWPObjectStore()
        let changed = try HWPCBOR.encode(mutate(try HWPCBOR.decode(try source.get(HWPReference(value: existing[0])))))
        var updated: [HWPValue] = [try store.add(changed).value]
        for part in existing.dropFirst() {
            updated.append(try store.add(try source.get(HWPReference(value: part))).value)
        }
        allLogs[0] = try replacing(allLogs[0], "parts", with: .array(updated))
        let newRoot = try store.put(try replacing(manifest, "logs", with: .array(allLogs)))
        return try store.pack(root: newRoot)
    }

    private func blockSizes(_ raw: Data) throws -> [Int] {
        let (store, root) = try HWPObjectStore.unpack(raw)
        let manifest = try store.object(root)
        var sizes: [Int] = []
        for log in try logs(manifest) {
            for part in try parts(log) {
                sizes.append(try openings(store.object(HWPReference(value: part))).count)
            }
        }
        return sizes
    }

    private func rejection(_ error: Error) -> HWPReject? { error as? HWPReject }

    // MARK: - Transport round trips

    func testFrozenPrivateTransportRoundTripsByteForByte() throws {
        let fixture = try fixture()
        for (name, select) in cases {
            let item = select(fixture)
            let raw = data(item.pack_hex)
            let reopened = try HWPDisclosure.unpack(raw)
            XCTAssertEqual(reopened, abiValue(item.value), "\(name): reopened value")
            XCTAssertEqual(try HWPDisclosure.pack(reopened), raw, "\(name): repack bytes")
            // The authored order is not the canonical order; `pack` must still match.
            XCTAssertEqual(try HWPDisclosure.pack(abiValue(item.input)), raw, "\(name): authored order")
            let counts = try logs(reopened).map { try openings($0).count }.sorted()
            XCTAssertEqual(counts, item.opening_counts.sorted(), "\(name): opening counts")
        }
    }

    func testFrozenChunkingUsesBoundedBlocks() throws {
        let fixture = try fixture()
        XCTAssertEqual(try blockSizes(data(fixture.chunked.pack_hex)), [256, 44])
        // Manifest logs are ordered by capture digest, not by authored order.
        XCTAssertEqual(try blockSizes(data(fixture.small.pack_hex)).sorted(), [2, 3])
        let full = try blockSizes(data(fixture.full.pack_hex))
        XCTAssertEqual(full.count, fixture.full.blocks)
        XCTAssertEqual(full.reduce(0, +), fixture.full.opening_counts.reduce(0, +))
        XCTAssertEqual(full.dropLast(), Array(repeating: HWPDisclosure.block, count: fixture.full.blocks - 1))
        XCTAssertEqual(try blockSizes(data(fixture.capture.pack_hex)), [4])
    }

    func testFrozenCompleteDisclosureRoundTripsAndOpensTheRealLadder() throws {
        let fixture = try fixture()
        let raw = data(fixture.full.pack_hex)
        let reopened = try HWPDisclosure.unpack(raw)
        XCTAssertEqual(try HWPDisclosure.pack(reopened), raw)
        XCTAssertEqual(try logs(reopened).count, 1)
        let captureOpenings = try openings(logs(reopened)[0])
        XCTAssertEqual(captureOpenings.count, fixture.full.opening_counts[0])
        XCTAssertEqual(captureOpenings.count, 1250)
        let (store, root) = try HWPObjectStore.unpack(raw)
        let manifest = try store.object(root)
        XCTAssertEqual(manifest.field("type"), .text("private-disclosure"))
        XCTAssertEqual(try parts(try logs(manifest)[0]).count, fixture.full.blocks)
        XCTAssertEqual(store.count, fixture.full.blocks + 1, "blocks plus the manifest")
        XCTAssertEqual(try logs(manifest)[0].field("capture")!.field("sha256"), .bytes(data(fixture.full.capture_hex)))

        let start = try HWPReference(value: referenceValue(fixture.full.start))
        let events = try HWPTranscript.open(start: start, count: fixture.full.count,
                                            root: data(fixture.full.root_hex), openings: captureOpenings)
        XCTAssertEqual(events.count, fixture.full.count)
        XCTAssertEqual(events.first?.field("kind"), .text("header"))
        XCTAssertEqual(events.last?.field("kind"), .text("end"))
    }

    func testChangedSaltEventCountAndOrderCannotOpenTheFrozenTranscript() throws {
        let fixture = try fixture()
        let reopened = try HWPDisclosure.unpack(data(fixture.full.pack_hex))
        let captureOpenings = try openings(logs(reopened)[0])
        let start = try HWPReference(value: referenceValue(fixture.full.start))
        let root = data(fixture.full.root_hex)
        let count = fixture.full.count

        let original = captureOpenings[0]
        var changedSalt = captureOpenings
        changedSalt[0] = try replacing(original, "salt", with: .bytes(Data(repeating: 0, count: 32)))
        var changedEvent = captureOpenings
        changedEvent[0] = try replacing(original, "event",
                                        with: .bytes(try HWPCBOR.encode(.map([HWPEntry(.text("kind"), .text("header"))]))))

        for (label, candidate) in [("salt", changedSalt), ("event", changedEvent)] {
            XCTAssertThrowsError(try HWPTranscript.open(start: start, count: count, root: root,
                                                        openings: candidate), label) { error in
                XCTAssertEqual(self.rejection(error), HWPReject("transcript-root"), label)
            }
        }
        XCTAssertThrowsError(try HWPTranscript.open(start: start, count: count - 1, root: root,
                                                    openings: captureOpenings)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("complete-disclosure-required"))
        }
        XCTAssertThrowsError(try HWPTranscript.open(start: start, count: count, root: root,
                                                    openings: Array(captureOpenings.dropLast()))) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("complete-disclosure-required"))
        }
        XCTAssertThrowsError(try HWPTranscript.open(start: start, count: count, root: root,
                                                    openings: [captureOpenings[1], captureOpenings[0]]
                                                        + captureOpenings.dropFirst(2))) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("opening-order"))
        }
        XCTAssertThrowsError(try HWPTranscript.open(start: start, count: count,
                                                    root: Data(repeating: 0, count: 32),
                                                    openings: captureOpenings)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("transcript-root"))
        }
    }

    // MARK: - Transcript commitment

    func testCommitAndOpenMatchFrozenCommitEvents() throws {
        let fixture = try fixture()
        let transcript = fixture.transcript
        let start = try HWPReference(value: referenceValue(transcript.start))
        let events = try transcript.events_hex.map { try HWPCBOR.decode(data($0)) }
        let salts = transcript.salts_hex.map(data)

        let (root, openings) = try HWPTranscript.commit(start: start, events: events, salts: salts)
        XCTAssertEqual(root, data(transcript.root_hex))
        XCTAssertEqual(openings.count, transcript.openings.count)
        for (index, opening) in openings.enumerated() {
            XCTAssertEqual(opening.field("index"), .unsigned(UInt64(index)))
            XCTAssertEqual(opening.field("salt"), .bytes(salts[index]))
            XCTAssertEqual(opening.field("event"), .bytes(data(transcript.events_hex[index])),
                           "opening \(index) event bytes")
        }
        XCTAssertEqual(try HWPTranscript.open(start: start, count: events.count, root: root,
                                              openings: openings), events)

        // Fresh salts must come from the platform CSPRNG and never repeat.
        let (freshRoot, freshOpenings) = try HWPTranscript.commit(start: start, events: events)
        let freshSalts = try freshOpenings.map { opening -> Data in
            guard case .bytes(let salt) = opening.field("salt")! else { throw HWPReject("test-shape") }
            return salt
        }
        XCTAssertEqual(freshSalts.count, events.count)
        XCTAssertEqual(Set(freshSalts).count, events.count)
        XCTAssertEqual(try HWPTranscript.open(start: start, count: events.count, root: freshRoot,
                                              openings: freshOpenings), events)

        XCTAssertThrowsError(try HWPTranscript.commit(start: start, events: events,
                                                      salts: [salts[0], salts[0], salts[2], salts[3]])) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("salt-count-or-reuse"))
        }
        XCTAssertThrowsError(try HWPTranscript.commit(start: start, events: [events[0]])) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("event-count"))
        }
        XCTAssertThrowsError(try HWPTranscript.open(start: start, count: 1, root: root, openings: openings)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("integer-domain"))
        }
    }

    // MARK: - Malformed and non-canonical transport

    func testMalformedAndNonCanonicalTransportRejects() throws {
        let fixture = try fixture()
        let small = data(fixture.small.pack_hex)

        XCTAssertThrowsError(try HWPDisclosure.unpack(Data(small.dropLast())), "truncated bundle")
        XCTAssertThrowsError(try HWPDisclosure.unpack(small + Data([0x00])), "trailing data")
        // The raw ABI map is an input to `pack`, never a transport bundle itself.
        XCTAssertThrowsError(try HWPDisclosure.unpack(try HWPCBOR.encode(abiValue(fixture.small.value))),
                             "raw ABI map is not a transport")

        let sharedCapture = abiValue(.init(logs: [fixture.small.value.logs[0], fixture.small.value.logs[0]],
                                           lineage_salts: []))
        XCTAssertThrowsError(try HWPDisclosure.pack(sharedCapture)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("duplicate-disclosed-session"))
        }
        let repeatedSalt = abiValue(.init(logs: fixture.salts.value.logs,
                                          lineage_salts: [fixture.salts.value.lineage_salts[0],
                                                          fixture.salts.value.lineage_salts[0]]))
        XCTAssertThrowsError(try HWPDisclosure.pack(repeatedSalt)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("duplicate-lineage-salt"))
        }

        let wrongType = try rebuildingManifest(small) { try self.replacing($0, "type", with: .text("not-disclosure")) }
        XCTAssertThrowsError(try HWPDisclosure.unpack(wrongType)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("object-version-or-type"))
        }

        var (store, root) = try HWPObjectStore.unpack(small)
        _ = try store.add(Data("unrelated-private-bytes".utf8))
        XCTAssertThrowsError(try HWPDisclosure.unpack(try store.pack(root: root))) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("unrelated-private-object"))
        }

        let chunked = data(fixture.chunked.pack_hex)
        let wrongOffset = try rebuildingFirstBlock(chunked) { try self.replacing($0, "offset", with: .unsigned(1)) }
        XCTAssertThrowsError(try HWPDisclosure.unpack(wrongOffset)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("opening-block-offset"))
        }
        let wrongSize = try rebuildingFirstBlock(chunked) { block in
            guard case .array(let openings) = block.field("openings")! else { throw HWPReject("test-shape") }
            return try self.replacing(block, "openings", with: .array(Array(openings.dropLast())))
        }
        XCTAssertThrowsError(try HWPDisclosure.unpack(wrongSize)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("opening-block-size"))
        }
        // Hostile opening fields must reject, never trap during budget accounting.
        for malformed in [HWPValue.null, .map([]), .map([HWPEntry(.text("event"), .bytes(Data([0xf6])))])] {
            let raw = try rebuildingFirstBlock(chunked) { block in
                var values = try self.openings(block); values[0] = malformed
                return try self.replacing(block, "openings", with: .array(values))
            }
            XCTAssertThrowsError(try HWPDisclosure.unpack(raw))
        }
        let wrongBlockCount = try rebuildingManifest(chunked) { try self.replacing($0, "logs", with: .array(
            self.logs($0).map { log in try self.replacing(log, "count", with: .unsigned(1250)) })) }
        XCTAssertThrowsError(try HWPDisclosure.unpack(wrongBlockCount)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("opening-block-count"))
        }

        // Reversed lineage salts survive decoding but not canonical repacking.
        let reordered = try XCTUnwrap(fixture.salts.reordered_pack_hex)
        XCTAssertThrowsError(try HWPDisclosure.unpack(data(reordered))) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("private-disclosure-noncanonical"))
        }
    }

    /// A sub-megabyte bundle can reference one block from 4096 captures and declare
    /// 1,024,000 openings. That declared history must be refused before allocation.
    func testSharedBlockAmplificationIsBoundedBeforeAllocation() throws {
        var openings: [HWPValue] = []
        for index in 0..<250 {
            openings.append(.map([
                HWPEntry(.text("index"), .unsigned(UInt64(index))),
                HWPEntry(.text("salt"), .bytes(Data(SHA256.hash(data: Data("amplified-salt-\(index)".utf8))))),
                HWPEntry(.text("event"), .bytes(try HWPCBOR.encode(.map([
                    HWPEntry(.text("i"), .unsigned(UInt64(index)))])))),
            ]))
        }
        let block = try HWPCBOR.encode(.map([
            HWPEntry(.text("v"), .text("hwp/0")),
            HWPEntry(.text("type"), .text("opening-block")),
            HWPEntry(.text("offset"), .unsigned(0)),
            HWPEntry(.text("openings"), .array(openings)),
        ]))
        var store = HWPObjectStore()
        let shared = try store.add(block).value
        let captures = (0..<4096)
            .map { Data(SHA256.hash(data: Data("amplified-capture-\($0)".utf8))) }
            .sorted { $0.lexicographicallyPrecedes($1) }
        let logs = captures.map { digest in
            HWPValue.map([
                HWPEntry(.text("capture"), .map([HWPEntry(.text("sha256"), .bytes(digest)),
                                                 HWPEntry(.text("size"), .unsigned(64))])),
                HWPEntry(.text("count"), .unsigned(250)),
                HWPEntry(.text("parts"), .array([shared])),
            ])
        }
        let root = try store.put(.map([
            HWPEntry(.text("v"), .text("hwp/0")),
            HWPEntry(.text("type"), .text("private-disclosure")),
            HWPEntry(.text("logs"), .array(logs)),
            HWPEntry(.text("lineage_salts"), .array([])),
        ]))
        let amplified = try store.pack(root: root)
        XCTAssertLessThan(amplified.count, 2 << 20, "the attack bundle stays small")
        XCTAssertThrowsError(try HWPDisclosure.unpack(amplified)) { error in
            XCTAssertEqual(self.rejection(error), HWPReject("disclosure-budget"))
        }
    }

    // MARK: - Frozen authority pins

    func testFrozenAuthorityPinsMatchProtocolFiles() throws {
        let fixture = try fixture()
        guard let root = protocolRoot() else {
            throw XCTSkip("set HWP_PROTOCOL_ROOT to verify the frozen authority pins")
        }
        for name in ["disclosure.py", "core.py"] {
            let path = root.appendingPathComponent("hwp0/\(name)")
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw XCTSkip("missing \(path.path)")
            }
            let digest = SHA256.hash(data: try Data(contentsOf: path)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, fixture.source_sha256[name], name)
        }
        // The interchange pin must agree with the vector pin the CBOR oracle already verifies.
        struct Expectations: Decodable { let source_sha256: String }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cbor-expectations", withExtension: "json",
                                                  subdirectory: "Fixtures"))
        let expectations = try JSONDecoder().decode(Expectations.self, from: try Data(contentsOf: url))
        XCTAssertEqual(fixture.source_sha256["interchange.json"], expectations.source_sha256)
    }

    private func protocolRoot() -> URL? {
        if let path = ProcessInfo.processInfo.environment["HWP_PROTOCOL_ROOT"] {
            return URL(fileURLWithPath: path)
        }
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { repository.deleteLastPathComponent() }
        let candidate = repository.appendingPathComponent("protocol/v0")
        return FileManager.default.fileExists(atPath: candidate.appendingPathComponent("hwp0/disclosure.py").path)
            ? candidate : nil
    }
}
