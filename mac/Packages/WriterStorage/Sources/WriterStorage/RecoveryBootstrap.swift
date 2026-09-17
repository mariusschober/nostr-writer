import CryptoKit
import Darwin
import Foundation
import Security

protocol RecoveryKeychainAdding: Sendable {
    func add(_ identity: RecoveryKeychainIdentity, bytes: Data) -> OSStatus
}

struct SystemRecoveryKeychainAdder: RecoveryKeychainAdding {
    func add(_ identity: RecoveryKeychainIdentity, bytes: Data) -> OSStatus {
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identity.service,
            kSecAttrAccount as String: identity.account,
            kSecAttrAccessGroup as String: identity.accessGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: bytes
        ] as CFDictionary, nil)
    }
}

/// Retained by the store, including while a caller holds only the store actor.
/// Descriptors never change; deinit releases the single-writer lease.
final class RecoveryInstallationLease: @unchecked Sendable {
    let directory: Int32
    private let lock: Int32
    init(directory: Int32, lock: Int32) { self.directory = directory; self.lock = lock }
    deinit { Darwin.close(lock); Darwin.close(directory) }
}

struct RecoveryBootstrapMarker: Codable {
    let version: Int
    let installation: UUID
    let service: String
    let accessGroup: String
    var ready: Bool
}

/// Establishes a private installation before SQLite can create any data.
/// The root's parent must be the app-owned Application Support directory.
/// No reset, key replacement, legacy Keychain fallback, or deletion is exposed.
public actor RecoveryBootstrap {
    private let reader: any RecoveryKeychainReading
    private let adder: any RecoveryKeychainAdding

    public init() {
        reader = SystemRecoveryKeychainReader(); adder = SystemRecoveryKeychainAdder()
    }
    init(reader: any RecoveryKeychainReading, adder: any RecoveryKeychainAdding) {
        self.reader = reader; self.adder = adder
    }

    public func open(root: URL, service: String, accessGroup: String) async throws -> DocumentStore {
        // Validate configuration before making even an empty directory.
        _ = try RecoveryKeychainIdentity(service: service, account: "validation", accessGroup: accessGroup)
        guard root.isFileURL, root.path == root.standardizedFileURL.resolvingSymlinksInPath().path else {
            throw failure("The private recovery location is not a direct local directory.")
        }
        let created = mkdir(root.path, 0o700) == 0
        guard created || errno == EEXIST else { throw failure("The private recovery directory could not be created.") }
        let directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw failure("The private recovery directory is unavailable.") }
        var transferred = false
        defer { if !transferred { Darwin.close(directory) } }
        var attributes = stat()
        guard fstat(directory, &attributes) == 0, attributes.st_uid == geteuid(),
              attributes.st_mode & 0o077 == 0 else {
            throw failure("The private recovery directory has unsafe ownership or permissions.")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        if !created && !names.contains("bootstrap.json") {
            throw failure("Existing private state has no installation marker. It was preserved for recovery.")
        }
        let lock = openat(directory, "installation.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw failure("The recovery installation cannot be locked.") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lock)
            throw failure("Another process owns this recovery installation.")
        }
        let lease = RecoveryInstallationLease(directory: directory, lock: lock)
        transferred = true
        var marker: RecoveryBootstrapMarker
        if created {
            marker = .init(version: 1, installation: UUID(), service: service, accessGroup: accessGroup, ready: false)
            try write(marker, directory: directory)
            let parent = Darwin.open(root.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard parent >= 0 else { throw failure("The new recovery location could not be synchronized.") }
            defer { Darwin.close(parent) }
            guard fsync(parent) == 0 else { throw failure("The new recovery location could not be synchronized.") }
        } else {
            marker = try read(directory: directory)
        }
        guard marker.version == 1, marker.service == service, marker.accessGroup == accessGroup else {
            throw failure("The recovery installation identity does not match this application.")
        }
        if !marker.ready {
            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
            guard Set(contents).isSubset(of: ["bootstrap.json", "installation.lock"]) else {
                throw failure("An incomplete installation contains private data. No key was created or replaced.")
            }
        }
        let identity = try RecoveryKeychainIdentity(service: service, account: marker.installation.uuidString,
                                                    accessGroup: accessGroup)
        let provider = KeychainRecoveryKey(identity: identity, reader: reader)
        do {
            _ = try await provider.loadRecoveryKey()
        } catch RecoveryKeyError.missing where !marker.ready {
            // Only a durable preparing marker with no data allows first creation.
            let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            let result = adder.add(identity, bytes: bytes)
            guard result == errSecSuccess || result == errSecDuplicateItem else {
                throw failure("The new recovery key could not be stored. Existing state was preserved; retry after restoring Keychain access.")
            }
            _ = try await provider.loadRecoveryKey() // Also validates a duplicate race; never delete it.
        }
        try Task.checkCancellation()
        if !marker.ready { marker.ready = true; try write(marker, directory: directory) }
        let store = try DocumentStore(configuration: .init(databaseURL: root.appendingPathComponent("recovery.sqlite"),
                                                           retentionPolicy: .rollingJournal), keyProvider: provider)
        await store.retainInstallationLease(lease)
        return store
    }

    private func failure(_ message: String) -> RecoveryKeyError { .unavailable(message) }

    private func read(directory: Int32) throws -> RecoveryBootstrapMarker {
        let fd = openat(directory, "bootstrap.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw failure("The recovery installation marker cannot be read.") }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_uid == geteuid(), attributes.st_mode & 0o077 == 0,
              attributes.st_size > 0, attributes.st_size <= 4096 else {
            throw failure("The recovery installation marker is malformed or unsafe.")
        }
        var bytes = Data(count: Int(attributes.st_size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count, let marker = try? JSONDecoder().decode(RecoveryBootstrapMarker.self, from: bytes) else {
            throw failure("The recovery installation marker is malformed. Existing files were preserved.")
        }
        return marker
    }

    private func write(_ marker: RecoveryBootstrapMarker, directory: Int32) throws {
        let bytes = try JSONEncoder().encode(marker)
        let name = "bootstrap-\(UUID().uuidString).pending"
        let fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw failure("The recovery installation marker could not be created.") }
        defer { Darwin.close(fd) }
        try bytes.withUnsafeBytes { buffer in
            var position = 0
            while position < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: position), buffer.count - position)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw failure("The recovery installation marker could not be written.") }
                position += count
            }
        }
        guard fsync(fd) == 0, renameat(directory, name, directory, "bootstrap.json") == 0,
              fsync(directory) == 0 else {
            throw failure("The recovery installation marker could not be committed. Existing state was preserved.")
        }
    }
}
