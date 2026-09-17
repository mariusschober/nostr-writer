import XCTest
@testable import WriterHWP

final class CommitmentTests: XCTestCase {
    private func hex(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        return Data(stride(from: 0, to: bytes.count, by: 2).map {
            UInt8(String(decoding: bytes[$0..<$0+2], as: UTF8.self), radix: 16)!
        })
    }
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    func testFrozenPrefixRootsAndConsistencyPathsAgreeExactly() throws {
        struct Oracle: Decodable {
            struct Path: Decodable { let old_count: Int; let new_count: Int; let path_hex: [String] }
            let consistency: [Path]; let leaves_hex: [String]; let prefix_roots_hex: [String]
        }
        let oracle = try JSONDecoder().decode(Oracle.self, from: fixture("merkle-oracle"))
        let leaves = oracle.leaves_hex.map(hex), roots = oracle.prefix_roots_hex.map(hex)
        for count in 0...leaves.count { XCTAssertEqual(try HWPMerkle.root(Array(leaves.prefix(count))), roots[count]) }
        for row in oracle.consistency {
            let path = row.path_hex.map(hex)
            XCTAssertEqual(try HWPMerkle.consistency(leaves, oldCount: row.old_count), path)
            XCTAssertTrue(try HWPMerkle.verifyConsistency(oldCount: row.old_count, newCount: row.new_count,
                oldRoot: roots[row.old_count], newRoot: roots[row.new_count], path: path))
            XCTAssertFalse(try HWPMerkle.verifyConsistency(oldCount: row.old_count, newCount: row.new_count,
                oldRoot: roots[row.old_count], newRoot: roots[row.new_count], path: path + [Data(repeating: 0, count: 32)]))
        }
    }
    func testFrozenSaltedCaptureLeavesAndSelectedOpeningsAgreeExactly() throws {
        struct Oracle: Decodable {
            struct Capture: Decodable {
                struct Opening: Decodable { let index: Int; let event_hex: String; let leaf_hex: String; let path_hex: [String]; let salt_hex: String }
                let start_digest: String; let count: Int; let root_hex: String; let openings: [Opening]
            }
            let capture: Capture
        }
        let capture = try JSONDecoder().decode(Oracle.self, from: fixture("merkle-oracle")).capture
        XCTAssertEqual(capture.openings.count, 4)
        for opening in capture.openings {
            let leaf = try HWPMerkle.leaf(startDigest: hex(capture.start_digest), index: opening.index,
                                          salt: hex(opening.salt_hex), event: hex(opening.event_hex))
            XCTAssertEqual(leaf, hex(opening.leaf_hex))
            XCTAssertTrue(try HWPMerkle.verifyInclusion(leaf: leaf, index: opening.index, count: capture.count,
                                                       path: opening.path_hex.map(hex), root: hex(capture.root_hex)))
            let changed = try HWPMerkle.leaf(startDigest: hex(capture.start_digest), index: opening.index,
                                             salt: Data(repeating: 0, count: 32), event: hex(opening.event_hex))
            XCTAssertFalse(try HWPMerkle.verifyInclusion(leaf: changed, index: opening.index, count: capture.count,
                                                        path: opening.path_hex.map(hex), root: hex(capture.root_hex)))
        }
    }
    func testEveryLeafAndPrefixAtUnbalancedTreeSizesAndTampering() throws {
        for count in [1,2,3,5,8,13,31] {
            let leaves = (0..<count).map { HWPMerkle.digest(Data("leaf-\($0)".utf8)) }
            let root = try HWPMerkle.root(leaves)
            for index in leaves.indices {
                let path = try HWPMerkle.inclusion(leaves, index: index)
                XCTAssertTrue(try HWPMerkle.verifyInclusion(leaf: leaves[index], index: index, count: count, path: path, root: root))
                XCTAssertFalse(try HWPMerkle.verifyInclusion(leaf: Data(repeating: 0, count: 32), index: index, count: count, path: path, root: root))
                XCTAssertFalse(try HWPMerkle.verifyInclusion(leaf: leaves[index], index: index, count: count, path: path + [root], root: root))
                if !path.isEmpty { XCTAssertFalse(try HWPMerkle.verifyInclusion(leaf: leaves[index], index: index, count: count, path: Array(path.dropLast()), root: root)) }
            }
            for previous in 1...count {
                let old = try HWPMerkle.root(Array(leaves.prefix(previous)))
                let path = try HWPMerkle.consistency(leaves, oldCount: previous)
                XCTAssertTrue(try HWPMerkle.verifyConsistency(oldCount: previous, newCount: count, oldRoot: old, newRoot: root, path: path))
                XCTAssertFalse(try HWPMerkle.verifyConsistency(oldCount: previous, newCount: count, oldRoot: Data(repeating: 0, count: 32), newRoot: root, path: path))
            }
        }
    }
    func testEmptyTreeAndHostileCountsFailSafely() throws {
        let empty = HWPMerkle.digest(Data())
        XCTAssertTrue(try HWPMerkle.verifyConsistency(oldCount: 0, newCount: 0, oldRoot: empty, newRoot: empty, path: []))
        XCTAssertFalse(try HWPMerkle.verifyConsistency(oldCount: Int.max, newCount: Int.min, oldRoot: empty, newRoot: empty, path: []))
        XCTAssertFalse(try HWPMerkle.verifyInclusion(leaf: empty, index: Int.min, count: -1, path: [], root: empty))
        XCTAssertThrowsError(try HWPMerkle.inclusion([], index: 0))
        XCTAssertThrowsError(try HWPMerkle.root([Data()]))
    }
    func testFrozenBundlesRoundTripEveryObjectByte() throws {
        var bundles = 0
        for row in try FrozenOracle.cborRows() where row.valid {
            let raw = hex(row.hex)
            let value = try HWPCBOR.decode(raw)
            if value.field("type") != .text("bundle") { continue }
            let result = try HWPObjectStore.unpack(raw)
            XCTAssertEqual(try result.store.pack(root: result.root), raw)
            XCTAssertNoThrow(try result.store.get(result.root))
            bundles += 1
        }
        XCTAssertGreaterThan(bundles, 10)
    }
    func testReferenceLengthDigestAndBundleEntriesCannotBeSubstituted() throws {
        var store = HWPObjectStore()
        let ref = try store.add(Data("exact source\r\n".utf8))
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(try store.add(Data("exact source\r\n".utf8)), ref)
        XCTAssertEqual(store.count, 1)
        XCTAssertThrowsError(try store.get(HWPReference(sha256: ref.sha256, size: ref.size - 1)))
        XCTAssertThrowsError(try store.get(HWPReference(sha256: Data(repeating: 0, count: 32), size: ref.size)))
        let raw = try store.pack(root: ref)
        let object = try HWPCBOR.decode(raw)
        guard case .map(let entries) = object, case .array(let rows) = object.field("objects") else { return XCTFail() }
        for replacement in [HWPValue.array(rows + rows), .array([.array([.bytes(ref.sha256), .bytes(Data("tampered".utf8))])])] {
            let changed = HWPValue.map(entries.map { $0.key == .text("objects") ? HWPEntry($0.key,replacement) : $0 })
            XCTAssertThrowsError(try HWPObjectStore.unpack(HWPCBOR.encode(changed)))
        }
    }
}
