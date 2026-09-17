import XCTest
import CryptoKit
import BigInt
@testable import WriterHWP

final class StrictCOSETests: XCTestCase {
    private struct Oracle: Decodable {
        struct Pair: Decodable { let signature: String; let key: String }
        struct Point: Decodable { let hex: String; let valid: Bool }
        let pairs: [Pair]; let points: [Point]
        let seed: String; let payload: String; let key: String; let signature: String
    }
    private func oracle() throws -> Oracle {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "cose-oracle", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url))
    }
    private func hex(_ text: String) -> Data {
        let bytes = Array(text.utf8)
        return Data(stride(from: 0, to: bytes.count, by: 2).map {
            UInt8(String(decoding: bytes[$0..<$0+2], as: UTF8.self), radix: 16)!
        })
    }
    func testNativeSigningPreservesExactHeadersPayloadAndInteroperableVerification() throws {
        let o = try oracle(), seed = hex(o.seed)
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        let payload = try HWPCBOR.decode(hex(o.payload))
        XCTAssertEqual(try HWPCOSE.publicKeyObject(privateKey.publicKey.rawRepresentation), hex(o.key))
        let signature = try HWPCOSE.sign(payload, with: privateKey)
        // CryptoKit intentionally randomizes Ed25519 signatures. Exact wire
        // agreement applies to the deterministic signed message and key; the
        // native signature is also checked by frozen Python in the external run.
        guard case .tag18(.array(let native)) = try HWPCBOR.decode(signature),
              case .tag18(.array(let reference)) = try HWPCBOR.decode(hex(o.signature)) else { return XCTFail() }
        XCTAssertEqual(Array(native.prefix(3)), Array(reference.prefix(3)))
        XCTAssertNoThrow(try HWPCOSE.verify(hex(o.signature), publicKeyObject: hex(o.key)))
        if let path = ProcessInfo.processInfo.environment["HWP_NATIVE_SIGNATURE_OUTPUT"] {
            let output = ["native": signature.map { String(format: "%02x", $0) }.joined(), "python": o.signature, "key": o.key]
            try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
        let verified = try HWPCOSE.verify(signature, publicKeyObject: hex(o.key))
        XCTAssertEqual(verified.payload, payload)
        XCTAssertEqual(verified.keyID, Data(SHA256.hash(data: hex(o.key))))
    }
    func testEveryCollectedFrozenSignatureVerifiesNatively() throws {
        let o = try oracle()
        XCTAssertFalse(o.pairs.isEmpty)
        for pair in o.pairs { XCTAssertNoThrow(try HWPCOSE.verify(hex(pair.signature), publicKeyObject: hex(pair.key))) }
    }
    func testStrictPointAdmissionMatchesFrozenArithmetic() throws {
        for point in try oracle().points {
            XCTAssertEqual(try HWPStrictEd25519.validPoint(hex(point.hex)), point.valid, point.hex)
        }
        XCTAssertFalse(try HWPStrictEd25519.validPoint(Data(repeating: 0, count: 31)))
    }
    func testSignatureMalleabilityWrongKeyAndChangedPayloadReject() throws {
        let o = try oracle(), raw = hex(o.signature), key = hex(o.key)
        guard case .tag18(.array(let fields)) = try HWPCBOR.decode(raw),
              case .bytes(let signature) = fields[3], case .bytes(let payload) = fields[2] else { return XCTFail() }
        let s = BigUInt(Data(signature.suffix(32).reversed())) + HWPStrictEd25519.subgroupOrder
        var scalar = Data(s.serialize().reversed()); scalar.append(Data(repeating: 0, count: 32 - scalar.count))
        var changed = fields; changed[3] = .bytes(Data(signature.prefix(32)) + scalar)
        XCTAssertThrowsError(try HWPCOSE.verify(HWPCBOR.encode(.tag18(.array(changed))), publicKeyObject: key))
        changed = fields; changed[2] = .bytes(payload + Data([0]))
        XCTAssertThrowsError(try HWPCOSE.verify(HWPCBOR.encode(.tag18(.array(changed))), publicKeyObject: key))
        let other = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 3, count: 32))
        XCTAssertThrowsError(try HWPCOSE.verify(raw, publicKeyObject: HWPCOSE.publicKeyObject(other.publicKey.rawRepresentation)))
        changed = fields; changed[1] = .map([HWPEntry(.unsigned(5), .unsigned(1))])
        XCTAssertThrowsError(try HWPCOSE.verify(HWPCBOR.encode(.tag18(.array(changed))), publicKeyObject: key))
    }
}
