import Foundation
import CryptoKit

extension HWPValue {
    public func field(_ name: String) -> HWPValue? {
        guard case .map(let entries) = self else { return nil }
        let key = HWPValue.text(name)
        return entries.first { $0.key == key }?.value
    }
    public func requireFields(_ names: [String]) throws {
        guard case .map(let entries) = self, entries.count == names.count,
              names.allSatisfy({ field($0) != nil }) else { throw HWPReject("object-fields") }
    }
    public func requireType(_ type: String, fields: [String]) throws {
        try requireFields(["v", "type"] + fields)
        guard field("v") == .text("hwp/0"), field("type") == .text(type) else { throw HWPReject("object-version-or-type") }
    }
}

public struct HWPReference: Hashable, Sendable {
    public let sha256: Data
    public let size: Int
    public init(sha256: Data, size: Int) throws {
        guard sha256.count == 32 else { throw HWPReject("byte-string-length") }
        guard (0...HWPCBOR.maximumBytes).contains(size) else { throw HWPReject("integer-domain") }
        self.sha256 = Data(sha256); self.size = size
    }
    public init(bytes: Data) throws {
        try self.init(sha256: Data(SHA256.hash(data: bytes)), size: bytes.count)
    }
    public init(value: HWPValue) throws {
        try value.requireFields(["sha256", "size"])
        guard case .bytes(let digest) = value.field("sha256"),
              case .unsigned(let count) = value.field("size"), count <= HWPCBOR.maximumBytes else {
            throw HWPReject("object-reference-domain")
        }
        try self.init(sha256: digest, size: Int(count))
    }
    public var value: HWPValue {
        .map([HWPEntry(.text("sha256"), .bytes(sha256)), HWPEntry(.text("size"), .unsigned(UInt64(size)))])
    }
}

/// Bounded, flat, content-addressed bytes. A reference never causes a network fetch.
public struct HWPObjectStore: Sendable {
    public static let maximumObjects = 4096
    private var objects: [Data: Data] = [:]
    private var byteCount = 0
    public init() {}
    public var count: Int { objects.count }

    @discardableResult
    public mutating func add(_ bytes: Data) throws -> HWPReference {
        let reference = try HWPReference(bytes: bytes)
        if let existing = objects[reference.sha256] {
            guard existing == bytes else { throw HWPReject("content-hash-collision") }
            return reference
        }
        guard objects.count < Self.maximumObjects else { throw HWPReject("object-count") }
        guard bytes.count <= HWPCBOR.maximumBytes - byteCount else { throw HWPReject("bundle-size") }
        objects[reference.sha256] = Data(bytes); byteCount += bytes.count
        return reference
    }
    @discardableResult
    public mutating func put(_ value: HWPValue) throws -> HWPReference { try add(HWPCBOR.encode(value)) }

    public func get(_ reference: HWPReference) throws -> Data {
        guard let bytes = objects[reference.sha256] else { throw HWPReject("missing-object") }
        // Verify length AND digest on every dereference, including cached values.
        guard bytes.count == reference.size, Data(SHA256.hash(data: bytes)) == reference.sha256 else {
            throw HWPReject("object-reference-mismatch")
        }
        return bytes
    }
    public func object(_ reference: HWPReference) throws -> HWPValue { try HWPCBOR.decode(get(reference)) }

    public func signed(_ reference: HWPReference) throws -> HWPVerifiedSignature {
        let raw = try get(reference)
        guard case .tag18(.array(let fields)) = try HWPCBOR.decode(raw), fields.count == 4,
              case .bytes(let protected) = fields[0], case .map(let headers) = try HWPCBOR.decode(protected),
              case .bytes(let keyID) = headers.first(where: { $0.key == .unsigned(4) })?.value,
              keyID.count == 32 else { throw HWPReject("signature-kid-missing") }
        guard let key = objects[keyID] else { throw HWPReject("missing-signature-key") }
        return try HWPCOSE.verify(raw, publicKeyObject: key)
    }

    public func pack(root: HWPReference) throws -> Data {
        _ = try get(root)
        let ordered = objects.keys.sorted { $0.lexicographicallyPrecedes($1) }
        return try HWPCBOR.encode(.map([
            HWPEntry(.text("v"), .text("hwp/0")), HWPEntry(.text("type"), .text("bundle")),
            HWPEntry(.text("root"), root.value),
            HWPEntry(.text("objects"), .array(ordered.map { .array([.bytes($0), .bytes(objects[$0]!)]) }))
        ]))
    }

    public static func unpack(_ raw: Data) throws -> (store: HWPObjectStore, root: HWPReference) {
        let value = try HWPCBOR.decode(raw)
        try value.requireType("bundle", fields: ["root", "objects"])
        guard case .array(let pairs) = value.field("objects"), pairs.count <= maximumObjects else { throw HWPReject("object-count") }
        var store = HWPObjectStore(), previous: Data?
        for pair in pairs {
            try Task.checkCancellation()
            guard case .array(let fields) = pair, fields.count == 2,
                  case .bytes(let digest) = fields[0], digest.count == 32,
                  case .bytes(let bytes) = fields[1] else { throw HWPReject("object-entry") }
            if let previous, !previous.lexicographicallyPrecedes(digest) { throw HWPReject("object-order-or-duplicate") }
            previous = digest
            guard Data(SHA256.hash(data: bytes)) == digest else { throw HWPReject("object-digest") }
            try store.add(bytes)
        }
        guard let rawRoot = value.field("root") else { throw HWPReject("object-fields") }
        let root = try HWPReference(value: rawRoot)
        _ = try store.get(root)
        return (store, root)
    }
}
