import Foundation
import CryptoKit
import BigInt

/// Public-only encoding and subgroup validation ported from frozen core.py.
/// Private signing and signature verification use CryptoKit's Ed25519 primitive.
public enum HWPStrictEd25519 {
    public static var subgroupOrder: BigUInt {
        (BigUInt(1) << 252) + BigUInt("27742317777372353535851937790883648493")
    }

    private struct Point { let x: BigUInt; let y: BigUInt; let z: BigUInt; let t: BigUInt }

    private static func add(_ left: Point, _ right: Point, prime: BigUInt, d: BigUInt) -> Point {
        let a = ((left.y + prime - left.x) * (right.y + prime - right.x)) % prime
        let b = ((left.y + left.x) * (right.y + right.x)) % prime
        let c = (2 * d * left.t * right.t) % prime
        let dd = (2 * left.z * right.z) % prime
        let e = (b + prime - a) % prime, f = (dd + prime - c) % prime
        let g = (dd + c) % prime, h = (b + a) % prime
        return Point(x: e*f % prime, y: g*h % prime, z: f*g % prime, t: e*h % prime)
    }

    public static func validPoint(_ raw: Data) throws -> Bool {
        try Task.checkCancellation()
        guard raw.count == 32 else { return false }
        let raw = Data(raw)
        let prime = (BigUInt(1) << 255) - 19
        let number = BigUInt(Data(raw.reversed()))
        let sign = number >> 255, y = number & ((BigUInt(1) << 255) - 1)
        guard y < prime else { return false }
        let d = (prime - 121665) * BigUInt(121666).power(prime - 2, modulus: prime) % prime
        let denominator = (d*y*y + 1) % prime
        guard denominator != 0 else { return false }
        let xSquared = (y*y + prime - 1) * denominator.power(prime - 2, modulus: prime) % prime
        var x = xSquared.power((prime + 3) / 8, modulus: prime)
        if x*x % prime != xSquared {
            let sqrtMinusOne = BigUInt(2).power((prime - 1) / 4, modulus: prime)
            x = x * sqrtMinusOne % prime
        }
        guard x*x % prime == xSquared, !(x == 0 && sign != 0) else { return false }
        if (x & 1) != sign { x = prime - x }
        guard !(x == 0 && y == 1) else { return false }
        var point = Point(x: x, y: y, z: 1, t: x*y % prime)
        var multiple = Point(x: 0, y: 1, z: 1, t: 0)
        var remaining = subgroupOrder
        while remaining != 0 {
            try Task.checkCancellation()
            if remaining & 1 != 0 { multiple = add(multiple, point, prime: prime, d: d) }
            point = add(point, point, prime: prime, d: d)
            remaining >>= 1
        }
        return multiple.x == 0 && (multiple.y + prime - multiple.z) % prime == 0
    }

    public static func canonicalSignature(_ signature: Data) throws -> Bool {
        guard signature.count == 64 else { return false }
        return try validPoint(Data(signature.prefix(32)))
            && BigUInt(Data(signature.suffix(32).reversed())) < subgroupOrder
    }
}

public struct HWPVerifiedSignature: Sendable {
    public let payload: HWPValue
    public let keyID: Data
}

public enum HWPCOSE {
    private static let externalAAD = Data("HWP/0".utf8)

    private static func value(_ map: HWPValue, _ key: HWPValue) -> HWPValue? {
        guard case .map(let entries) = map else { return nil }
        return entries.first { $0.key == key }?.value
    }

    private static func exactKeys(_ map: HWPValue, _ keys: [HWPValue]) -> Bool {
        guard case .map(let entries) = map, entries.count == keys.count else { return false }
        return keys.allSatisfy { key in entries.contains { $0.key == key } }
    }

    private static func bytes(_ value: HWPValue?, count: Int? = nil) throws -> Data {
        guard case .bytes(let bytes) = value, bytes.count <= HWPCBOR.maximumBytes else {
            throw HWPReject("byte-string-domain")
        }
        guard count == nil || bytes.count == count else { throw HWPReject("byte-string-length") }
        return bytes
    }

    public static func publicKeyObject(_ raw: Data) throws -> Data {
        guard try HWPStrictEd25519.validPoint(raw) else { throw HWPReject("ed25519-public-point") }
        return try HWPCBOR.encode(.map([
            HWPEntry(.unsigned(1), .unsigned(1)), HWPEntry(.unsigned(3), .negative(-19)),
            HWPEntry(.negative(-1), .unsigned(6)), HWPEntry(.negative(-2), .bytes(raw))
        ]))
    }

    public static func parsePublicKey(_ raw: Data) throws -> Data {
        let object = try HWPCBOR.decode(raw)
        guard exactKeys(object, [.unsigned(1), .unsigned(3), .negative(-1), .negative(-2)]) else {
            throw HWPReject("cose-key-fields")
        }
        guard value(object, .unsigned(1)) == .unsigned(1), value(object, .unsigned(3)) == .negative(-19),
              value(object, .negative(-1)) == .unsigned(6) else { throw HWPReject("cose-key-profile") }
        let publicBytes = try bytes(value(object, .negative(-2)), count: 32)
        guard try HWPStrictEd25519.validPoint(publicBytes) else { throw HWPReject("ed25519-public-point") }
        return publicBytes
    }

    public static func sign(_ payload: HWPValue, with key: Curve25519.Signing.PrivateKey) throws -> Data {
        guard value(payload, .text("v")) == .text("hwp/0") else { throw HWPReject("signature-payload-version") }
        let encodedKey = try publicKeyObject(key.publicKey.rawRepresentation)
        let protected = try HWPCBOR.encode(.map([
            HWPEntry(.unsigned(1), .negative(-19)), HWPEntry(.unsigned(3), .text("application/cbor")),
            HWPEntry(.unsigned(4), .bytes(Data(SHA256.hash(data: encodedKey))))
        ]))
        let body = try HWPCBOR.encode(payload)
        let message = try HWPCBOR.encode(.array([.text("Signature1"), .bytes(protected), .bytes(externalAAD), .bytes(body)]))
        let signature = try key.signature(for: message)
        guard try HWPStrictEd25519.validPoint(Data(signature.prefix(32))) else { throw HWPReject("ed25519-signature-point") }
        return try HWPCBOR.encode(.tag18(.array([.bytes(protected), .map([]), .bytes(body), .bytes(signature)])))
    }

    public static func verify(_ raw: Data, publicKeyObject key: Data) throws -> HWPVerifiedSignature {
        let object = try HWPCBOR.decode(raw)
        guard case .tag18(.array(let fields)) = object, fields.count == 4 else { throw HWPReject("cose-sign1") }
        guard fields[1] == .map([]) else { throw HWPReject("unprotected-headers-forbidden") }
        let protected = try bytes(fields[0]), payload = try bytes(fields[2]), signature = try bytes(fields[3], count: 64)
        let headers = try HWPCBOR.decode(protected)
        guard exactKeys(headers, [.unsigned(1), .unsigned(3), .unsigned(4)]),
              value(headers, .unsigned(1)) == .negative(-19), value(headers, .unsigned(3)) == .text("application/cbor") else {
            throw HWPReject("protected-headers")
        }
        let keyID = try bytes(value(headers, .unsigned(4)), count: 32)
        guard keyID == Data(SHA256.hash(data: key)) else { throw HWPReject("signature-key-binding") }
        let publicBytes = try parsePublicKey(key)
        guard try HWPStrictEd25519.canonicalSignature(signature) else { throw HWPReject("ed25519-signature-canonicality") }
        let message = try HWPCBOR.encode(.array([.text("Signature1"), .bytes(protected), .bytes(externalAAD), .bytes(payload)]))
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        guard publicKey.isValidSignature(signature, for: message) else { throw HWPReject("signature-invalid") }
        let body = try HWPCBOR.decode(payload)
        guard value(body, .text("v")) == .text("hwp/0") else { throw HWPReject("signed-payload-version") }
        return HWPVerifiedSignature(payload: body, keyID: keyID)
    }
}
