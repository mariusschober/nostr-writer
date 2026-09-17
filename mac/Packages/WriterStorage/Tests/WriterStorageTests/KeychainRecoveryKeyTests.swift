import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XCTest
import os
@testable import WriterStorage

private struct KeychainReadProbe: RecoveryKeychainReading {
    struct State: Sendable {
        var result: RecoveryKeychainRead
        var calls = 0
        var calledOnMainThread = false
    }
    let state: OSAllocatedUnfairLock<State>
    init(_ result: RecoveryKeychainRead) { state = .init(initialState: State(result: result)) }
    func copyMatching(_ identity: RecoveryKeychainIdentity) -> RecoveryKeychainRead {
        state.withLock {
            $0.calls += 1; $0.calledOnMainThread = $0.calledOnMainThread || Thread.isMainThread
            return $0.result
        }
    }
}

@MainActor
final class KeychainRecoveryKeyTests: XCTestCase {
    private func identity() throws -> RecoveryKeychainIdentity {
        try .init(service: "com.example.writer.test.recovery", account: "synthetic-installation",
                  accessGroup: "TESTTEAM01.com.example.writer.test")
    }
    private func validRead() throws -> RecoveryKeychainRead {
        let id = try identity()
        return .init(status: errSecSuccess, bytes: Data(repeating: 0x73, count: 32),
                     service: id.service, account: id.account, accessGroup: id.accessGroup,
                     accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                     synchronizable: false)
    }

    func testQueryIsExactNoninteractiveAndUsesDataProtection() throws {
        let id = try identity(), context = LAContext()
        context.interactionNotAllowed = true; defer { context.invalidate() }
        let query = SystemRecoveryKeychainReader.query(id, context: context)
        XCTAssertEqual(query.count, 10)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, id.service)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, id.account)
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, id.accessGroup)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(query[kSecMatchLimit as String] as? String, kSecMatchLimitOne as String)
        XCTAssertEqual(query[kSecReturnAttributes as String] as? Bool, true)
        XCTAssertEqual(query[kSecReturnData as String] as? Bool, true)
        XCTAssertTrue((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
        // Accessibility is validated on the returned item; filtering it in the
        // query would misclassify a wrong-policy existing item as missing.
        XCTAssertNil(query[kSecAttrAccessible as String])
        XCTAssertNil(query[kSecValueData as String])
    }

    func testReadIsOffMainActorAndDoesNotCacheKeyAcrossDenial() async throws {
        let probe = KeychainReadProbe(try validRead())
        let provider = KeychainRecoveryKey(identity: try identity(), reader: probe)
        let key = try await provider.loadRecoveryKey()
        XCTAssertEqual(key.withUnsafeBytes { Data($0) }, Data(repeating: 0x73, count: 32))
        probe.state.withLock { $0.result = .init(status: errSecInteractionNotAllowed) }
        do { _ = try await provider.loadRecoveryKey(); XCTFail("Access denial was bypassed") }
        catch { guard case RecoveryKeyError.locked = error else { return XCTFail("Wrong failure category") } }
        XCTAssertEqual(probe.state.withLock { $0.calls }, 2)
        XCTAssertFalse(probe.state.withLock { $0.calledOnMainThread })
    }

    func testStatusFailuresRemainDistinctAndNeverRetry() async throws {
        let cases: [(OSStatus, String)] = [
            (errSecItemNotFound, "missing"), (errSecAuthFailed, "denied"),
            (errSecUserCanceled, "denied"), (errSecInteractionNotAllowed, "locked"),
            (errSecInteractionRequired, "locked"), (errSecMissingEntitlement, "unavailable"),
            (errSecDecode, "unavailable"), (errSecNotAvailable, "unavailable")
        ]
        for (status, expected) in cases {
            let probe = KeychainReadProbe(.init(status: status))
            let provider = KeychainRecoveryKey(identity: try identity(), reader: probe)
            do { _ = try await provider.loadRecoveryKey(); XCTFail("Unavailable key was accepted") }
            catch let error as RecoveryKeyError {
                let category: String
                switch error {
                case .missing: category = "missing"
                case .denied: category = "denied"
                case .locked: category = "locked"
                case .unavailable: category = "unavailable"
                }
                XCTAssertEqual(category, expected)
            }
            XCTAssertEqual(probe.state.withLock { $0.calls }, 1)
        }
    }

    func testMalformedOrWrongIdentityAndPolicyAreRefused() async throws {
        let original = try validRead()
        var cases = [RecoveryKeychainRead(status: errSecSuccess)]
        for length in [0, 31, 33] { var bad = original; bad.bytes = Data(repeating: 0, count: length); cases.append(bad) }
        var bad = original; bad.service = "wrong-service"; cases.append(bad)
        bad = original; bad.account = "wrong-account"; cases.append(bad)
        bad = original; bad.accessGroup = "wrong-group"; cases.append(bad)
        bad = original; bad.accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String; cases.append(bad)
        bad = original; bad.synchronizable = true; cases.append(bad)
        bad = original; bad.synchronizable = nil; cases.append(bad)
        for result in cases {
            let provider = KeychainRecoveryKey(identity: try identity(), reader: KeychainReadProbe(result))
            do { _ = try await provider.loadRecoveryKey(); XCTFail("Wrong-policy key was accepted") }
            catch { guard case RecoveryKeyError.unavailable = error else { return XCTFail("Wrong failure category") } }
        }
    }

    func testInvalidIdentityCannotProduceBroadQuery() throws {
        for value in ["", "*", "contains space", "line\nfeed", "nul\0", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(try RecoveryKeychainIdentity(service: value, account: "test", accessGroup: "test"))
            XCTAssertThrowsError(try RecoveryKeychainIdentity(service: "test", account: value, accessGroup: "test"))
            XCTAssertThrowsError(try RecoveryKeychainIdentity(service: "test", account: "test", accessGroup: value))
        }
    }

    func testNativeResultDecoderDoesNotInventMissingAttributes() throws {
        let id = try identity()
        let attributes: [String: Any] = [
            kSecValueData as String: Data(repeating: 0x73, count: 32),
            kSecAttrService as String: id.service, kSecAttrAccount as String: id.account,
            kSecAttrAccessGroup as String: id.accessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let result = SystemRecoveryKeychainReader.decode(status: errSecSuccess, result: attributes as CFDictionary)
        XCTAssertEqual(result.bytes?.count, 32); XCTAssertEqual(result.synchronizable, false)
        XCTAssertEqual(result.accessibility, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        let missing = SystemRecoveryKeychainReader.decode(status: errSecSuccess, result: [:] as CFDictionary)
        XCTAssertNil(missing.bytes); XCTAssertNil(missing.synchronizable); XCTAssertNil(missing.accessibility)
        let error = SystemRecoveryKeychainReader.decode(status: errSecAuthFailed, result: attributes as CFDictionary)
        XCTAssertNil(error.bytes)
    }
}
