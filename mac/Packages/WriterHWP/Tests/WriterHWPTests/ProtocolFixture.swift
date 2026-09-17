import Foundation
import CryptoKit
@testable import WriterHWP

struct ProtocolFixture {
    struct Vector: Decodable {
        struct Case: Decodable {
            let id: String; let bundle: String; let document: String; let policy: String
            let policy_pin: String; let disclosures: String; let expected_class_v: String
        }
        let cases: [Case]; let objects: [String: String]
    }
    struct Oracle: Decodable {
        struct Row: Decodable {
            let id: String; let `public`: String; let recomputation: String; let no_witness: String
            let computed: String?; let lineage: String?; let evaluation_reject: String?
        }
        let vector_sha256: String; let cases: [Row]
    }
    let vector: Vector
    let oracle: Oracle
    let objects: [String: Data]
    init() throws {
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { repository.deleteLastPathComponent() }
        let root = ProcessInfo.processInfo.environment["HWP_PROTOCOL_ROOT"].map(URL.init(fileURLWithPath:)) ?? repository.appendingPathComponent("protocol/v0")
        guard let oracleURL = Bundle.module.url(forResource: "protocol-oracle", withExtension: "json", subdirectory: "Fixtures") else { throw HWPReject("test-oracle-missing") }
        oracle = try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: oracleURL))
        let raw = try Data(contentsOf: root.appendingPathComponent("vectors/interchange.json"))
        guard HWPMerkle.digest(raw) == (try Self.hex(oracle.vector_sha256)) else { throw HWPReject("frozen-vector-changed") }
        vector = try JSONDecoder().decode(Vector.self, from: raw)
        var objects: [String: Data] = [:]
        for (key, value) in vector.objects {
            let data = try Self.hex(value)
            guard HWPMerkle.digest(data) == (try Self.hex(key)) else { throw HWPReject("frozen-object-changed") }
            objects[key] = data
        }
        self.objects = objects
    }
    static func hex(_ hex: String) throws -> Data {
        let input = Array(hex.utf8)
        guard input.count % 2 == 0 else { throw HWPReject("test-hex") }
        func digit(_ n: UInt8) throws -> UInt8 {
            if n >= 48 && n <= 57 { return n - 48 }
            if n >= 97 && n <= 102 { return n - 87 }
            throw HWPReject("test-hex")
        }
        return try Data(stride(from: 0, to: input.count, by: 2).map { try digit(input[$0]) * 16 + digit(input[$0 + 1]) })
    }
    func bytes(_ key: String) throws -> Data { try objects[key].orReject("test-object-missing") }
    func row(_ id: String) throws -> Vector.Case { try vector.cases.first { $0.id == id }.orReject("test-case-missing") }
    func policy(_ row: Vector.Case) throws -> HWPVerificationPolicy {
        try HWPVerificationPolicy(bytes: bytes(row.policy), expectedSHA256: Self.hex(row.policy_pin))
    }
    func privateValue(_ row: Vector.Case) throws -> HWPValue { try HWPCBOR.decode(bytes(row.disclosures)) }
    static func replacing(_ object: HWPValue, _ field: String, _ replacement: HWPValue) throws -> HWPValue {
        guard case .map(let entries) = object, object.field(field) != nil else { throw HWPReject("test-object-fields") }
        return .map(entries.map { $0.key == .text(field) ? HWPEntry($0.key, replacement) : $0 })
    }
    static func fixtureKey(_ label: String) throws -> Curve25519.Signing.PrivateKey {
        // Exact public TEST-ONLY seed convention from frozen tests/support.py.
        try .init(rawRepresentation: HWPMerkle.digest(Data(("HWP-v0 PUBLIC FIXTURE: " + label).utf8)))
    }
}
