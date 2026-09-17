import CryptoKit
import Foundation
import WriterFoundation

/// Fixed encoding of the authenticated recovery snapshot format.
///
/// The additional authenticated data binds the ciphertext to one exact source
/// identity: format and domain, document identity, recovery stream identity,
/// monotonic chunk index, the full 64-bit source revision, the exact source
/// digest and byte count, and the previous committed chunk reference. The
/// encoding is byte-for-byte fixed so it cannot drift silently between writers.
enum RecoveryCipher {
    /// Domain separator for the AEAD additional data.
    static let aadDomain = Data("NWRECOVERY1".utf8)
    /// Version of the additional-data layout.
    static let aadVersion: UInt16 = 1
    /// Domain separator over the stored ciphertext, forming the chunk reference.
    static let chunkReferenceDomain = Data("NWCHUNKREF1".utf8)
    /// Domain separator for the installation key check value.
    static let keyCheckDomain = Data("NWRKEYCHK1".utf8)

    static let nonceByteCount = 12
    static let tagByteCount = 16
    static let digestByteCount = 32
    static let referenceByteCount = 32
    static let keyByteCount = 32

    /// Total fixed length of the additional-data encoding.
    /// 11 (domain) + 2 (version) + 16 + 16 + 8 + 8 + 32 + 8 + 32 = 133 bytes.
    static let aadByteCount = 133

    /// A stream's first snapshot binds a zero previous reference.
    static let genesisReference = Data(repeating: 0, count: referenceByteCount)

    static func aad(
        documentID: DocumentID,
        streamID: RecoveryStreamID,
        chunkIndex: UInt64,
        revision: Revision,
        sourceDigest: Data,
        byteCount: Int,
        previousReference: Data
    ) -> Data {
        var out = Data(capacity: aadByteCount)
        out.append(aadDomain)
        out.append(StorageEncoding.uint16(aadVersion))
        out.append(StorageEncoding.uuid(documentID.rawValue))
        out.append(StorageEncoding.uuid(streamID.rawValue))
        out.append(StorageEncoding.uint64(chunkIndex))
        out.append(StorageEncoding.uint64(revision.rawValue))
        out.append(sourceDigest)
        out.append(StorageEncoding.uint64(UInt64(bitPattern: Int64(byteCount))))
        out.append(previousReference)
        return out
    }

    static func chunkReference(
        documentID: DocumentID,
        streamID: RecoveryStreamID,
        chunkIndex: UInt64,
        nonce: Data,
        sealed: Data
    ) -> Data {
        var out = Data()
        out.append(chunkReferenceDomain)
        out.append(StorageEncoding.uuid(documentID.rawValue))
        out.append(StorageEncoding.uuid(streamID.rawValue))
        out.append(StorageEncoding.uint64(chunkIndex))
        out.append(nonce)
        out.append(sealed)
        return SourceSnapshot.sha256(out)
    }

    /// A fast, non-secret commitment to the installation key. It lets the store
    /// refuse an available-but-wrong key before it writes anything, and never
    /// replaces an inaccessible key.
    static func keyCheckValue(for key: SymmetricKey) throws -> Data {
        let raw = key.withUnsafeBytes { Data($0) }
        guard raw.count == keyByteCount else {
            throw StorageError.invariantViolation("The recovery key must be exactly 32 bytes.")
        }
        return SourceSnapshot.sha256(keyCheckDomain + raw)
    }

    /// Seals the source bytes and returns ciphertext followed by the tag.
    static func seal(_ plaintext: Data, key: SymmetricKey, nonce: Data, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.seal(plaintext, using: key, nonce: try nonceBox(nonce), authenticating: aad)
            return box.ciphertext + box.tag
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.invariantViolation("The recovery snapshot could not be sealed.")
        }
    }

    /// Opens ciphertext-plus-tag. Any authentication failure is a hard tamper signal.
    static func open(_ sealed: Data, key: SymmetricKey, nonce: Data, aad: Data) throws -> Data {
        guard sealed.count >= tagByteCount else {
            throw StorageError.tamperDetected("The stored recovery ciphertext is truncated.")
        }
        let ciphertext = sealed.prefix(sealed.count - tagByteCount)
        let tag = sealed.suffix(tagByteCount)
        do {
            let box = try AES.GCM.SealedBox(nonce: try nonceBox(nonce), ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.tamperDetected("The recovery snapshot failed authenticated decryption.")
        }
    }

    private static func nonceBox(_ data: Data) throws -> AES.GCM.Nonce {
        guard data.count == nonceByteCount else {
            throw StorageError.tamperDetected("The recovery nonce has an unexpected length.")
        }
        do {
            return try AES.GCM.Nonce(data: data)
        } catch {
            throw StorageError.tamperDetected("The recovery nonce is not usable.")
        }
    }
}
