import Foundation
import CryptoKit
@testable import WriterHWP

enum FrozenOracle {
    struct Row { let id: String; let hex: String; let valid: Bool }
    static func cborRows() throws -> [Row] {
        struct Vectors: Decodable {
            let canonical_cbor_hex: [String]; let reject_cbor_hex: [String]; let objects: [String: String]
        }
        struct Expectations: Decodable { let source_sha256: String; let objects: [String: Bool] }
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { repository.deleteLastPathComponent() }
        let root = ProcessInfo.processInfo.environment["HWP_PROTOCOL_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("protocol/v0")
        let raw = try Data(contentsOf: root.appendingPathComponent("vectors/interchange.json"))
        guard let expectationsURL = Bundle.module.url(forResource: "cbor-expectations", withExtension: "json", subdirectory: "Fixtures") else {
            throw HWPReject("missing-test-expectations")
        }
        let expected = try JSONDecoder().decode(Expectations.self, from: Data(contentsOf: expectationsURL))
        let digest = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        guard digest == expected.source_sha256 else { throw HWPReject("frozen-test-vector-digest-mismatch") }
        let vector = try JSONDecoder().decode(Vectors.self, from: raw)
        guard Set(vector.objects.keys) == Set(expected.objects.keys) else { throw HWPReject("frozen-test-object-set-mismatch") }
        var rows = vector.canonical_cbor_hex.enumerated().map { Row(id: "canonical-\($0.offset)", hex: $0.element, valid: true) }
        rows += vector.reject_cbor_hex.enumerated().map { Row(id: "rejected-\($0.offset)", hex: $0.element, valid: false) }
        rows += vector.objects.sorted { $0.key < $1.key }.map { Row(id: $0.key, hex: $0.value, valid: expected.objects[$0.key]!) }
        return rows
    }
}
