import CryptoKit
import Foundation
import Security
import XCTest
import os
@testable import WriterStorage

private struct BootstrapKeychain: RecoveryKeychainReading, RecoveryKeychainAdding {
    struct State: Sendable {
        var key: Data?
        var identity: RecoveryKeychainIdentity?
        var forcedRead: OSStatus?
        var addStatus = errSecSuccess
        var additions = 0
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    func copyMatching(_ identity: RecoveryKeychainIdentity) -> RecoveryKeychainRead {
        state.withLock {
            if let forced = $0.forcedRead { return .init(status: forced) }
            guard let key = $0.key, $0.identity == identity else { return .init(status: errSecItemNotFound) }
            return .init(status: errSecSuccess, bytes: key, service: identity.service,
                         account: identity.account, accessGroup: identity.accessGroup,
                         accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                         synchronizable: false)
        }
    }
    func add(_ identity: RecoveryKeychainIdentity, bytes: Data) -> OSStatus {
        state.withLock {
            $0.additions += 1
            guard $0.addStatus == errSecSuccess else { return $0.addStatus }
            $0.key = bytes; $0.identity = identity
            return errSecSuccess
        }
    }
}

@MainActor
final class RecoveryBootstrapTests: XCTestCase {
    private let service = "com.example.writer.test.recovery"
    private let group = "TESTTEAM01.com.example.writer.test"
    private func root() throws -> URL {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("writer-bootstrap-\(UUID())")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: parent) }
        return parent.appendingPathComponent("PrivateRecovery")
    }
    private func marker(_ root: URL) throws -> RecoveryBootstrapMarker {
        try JSONDecoder().decode(RecoveryBootstrapMarker.self, from: Data(contentsOf: root.appendingPathComponent("bootstrap.json")))
    }
    private func open(_ bootstrap: RecoveryBootstrap, _ root: URL) async throws -> DocumentStore {
        try await bootstrap.open(root: root, service: service, accessGroup: group)
    }

    func testNewInstallationCreatesOnceAndReopensSameIdentity() async throws {
        let root = try root(), keychain = BootstrapKeychain()
        let bootstrap = RecoveryBootstrap(reader: keychain, adder: keychain)
        let first = try await open(bootstrap, root)
        let initial = try marker(root)
        XCTAssertTrue(initial.ready)
        XCTAssertEqual(keychain.state.withLock { $0.key?.count }, 32)
        try await first.close()
        let second = try await open(bootstrap, root)
        XCTAssertEqual(try marker(root).installation, initial.installation)
        XCTAssertEqual(keychain.state.withLock { $0.additions }, 1)
        try await second.close()
    }

    func testReadyMissingKeyPreservesDatabaseAndNeverReplacesKey() async throws {
        let root = try root(), keychain = BootstrapKeychain()
        let bootstrap = RecoveryBootstrap(reader: keychain, adder: keychain)
        let store = try await open(bootstrap, root); try await store.close()
        let before = try Data(contentsOf: root.appendingPathComponent("recovery.sqlite"))
        keychain.state.withLock { $0.key = nil }
        do { _ = try await open(bootstrap, root); XCTFail("Missing ready key was replaced") }
        catch { XCTAssertEqual(error as? RecoveryKeyError, .missing) }
        XCTAssertEqual(keychain.state.withLock { $0.additions }, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("recovery.sqlite")), before)
    }

    func testDeniedPreparingKeyDoesNotCreateKeyOrDatabase() async throws {
        let root = try root(), keychain = BootstrapKeychain()
        keychain.state.withLock { $0.forcedRead = errSecAuthFailed }
        let bootstrap = RecoveryBootstrap(reader: keychain, adder: keychain)
        do { _ = try await open(bootstrap, root); XCTFail("Denied key was bypassed") }
        catch { guard case RecoveryKeyError.denied = error else { return XCTFail("Wrong failure") } }
        XCTAssertFalse(try marker(root).ready)
        XCTAssertEqual(keychain.state.withLock { $0.additions }, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("recovery.sqlite").path))
    }

    func testInterruptedFirstCreationCanResumeOnlyEmptyPreparingInstallation() async throws {
        let root = try root(), keychain = BootstrapKeychain()
        keychain.state.withLock { $0.addStatus = errSecNotAvailable }
        let bootstrap = RecoveryBootstrap(reader: keychain, adder: keychain)
        do { _ = try await open(bootstrap, root); XCTFail("Failed addition accepted") } catch {}
        let installation = try marker(root).installation
        keychain.state.withLock { $0.addStatus = errSecSuccess }
        let store = try await open(bootstrap, root)
        XCTAssertEqual(try marker(root).installation, installation)
        XCTAssertTrue(try marker(root).ready)
        try await store.close()
    }

    func testUnknownExistingRootAndPreparingRootWithDataArePreserved() async throws {
        let root = try root(), keychain = BootstrapKeychain()
        let bootstrap = RecoveryBootstrap(reader: keychain, adder: keychain)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do { _ = try await open(bootstrap, root); XCTFail("Existing empty root treated as new") } catch {}
        let root2 = try self.root()
        keychain.state.withLock { $0.addStatus = errSecNotAvailable }
        do { _ = try await open(bootstrap, root2); XCTFail("Failed addition accepted") } catch {}
        let content = Data("synthetic existing ciphertext".utf8)
        try content.write(to: root2.appendingPathComponent("recovery.sqlite"))
        keychain.state.withLock { $0.addStatus = errSecSuccess }
        do { _ = try await open(bootstrap, root2); XCTFail("Existing data permitted key creation") } catch {}
        XCTAssertEqual(keychain.state.withLock { $0.additions }, 1)
        XCTAssertEqual(try Data(contentsOf: root2.appendingPathComponent("recovery.sqlite")), content)
    }

    func testLiveStoreOwnsExclusiveLeaseUntilClose() async throws {
        let root = try root(), keychain = BootstrapKeychain()
        let bootstrap = RecoveryBootstrap(reader: keychain, adder: keychain)
        let store = try await open(bootstrap, root)
        do { _ = try await open(bootstrap, root); XCTFail("A second store acquired the installation") } catch {}
        XCTAssertEqual(keychain.state.withLock { $0.additions }, 1)
        try await store.close()
        let reopened = try await open(bootstrap, root); try await reopened.close()
    }
}
