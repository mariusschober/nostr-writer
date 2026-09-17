import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// One app-owned item, never a search for identities or other applications' keys.
/// The access group must come from legitimate application signing configuration.
/// No team identifier is manufactured by this component.
public struct RecoveryKeychainIdentity: Sendable, Equatable {
    public let service: String
    public let account: String
    public let accessGroup: String

    public init(service: String, account: String, accessGroup: String) throws {
        for value in [service, account, accessGroup] {
            guard !value.isEmpty, value.utf8.count <= 255,
                  value.utf8.allSatisfy({
                      (65...90).contains($0) || (97...122).contains($0) ||
                      (48...57).contains($0) || [45, 46, 95].contains($0)
                  }) else {
                throw RecoveryKeyError.unavailable("The recovery key identity is not configured correctly.")
            }
        }
        self.service = service; self.account = account; self.accessGroup = accessGroup
    }
}

// Only Sendable values cross the service boundary. Security dictionaries and
// LAContext stay inside the synchronous query on the recovery actor's executor.
struct RecoveryKeychainRead: Sendable {
    let status: OSStatus
    var bytes: Data?
    var service: String?
    var account: String?
    var accessGroup: String?
    var accessibility: String?
    var synchronizable: Bool?
}

/// Deliberately read-only: no add, update, delete or enumeration capability.
protocol RecoveryKeychainReading: Sendable {
    func copyMatching(_ identity: RecoveryKeychainIdentity) -> RecoveryKeychainRead
}

struct SystemRecoveryKeychainReader: RecoveryKeychainReading {
    func copyMatching(_ identity: RecoveryKeychainIdentity) -> RecoveryKeychainRead {
        let context = LAContext()
        context.interactionNotAllowed = true
        defer { context.invalidate() }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(Self.query(identity, context: context) as CFDictionary, &result)
        return Self.decode(status: status, result: result)
    }

    static func query(_ identity: RecoveryKeychainIdentity, context: LAContext) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: identity.service,
            kSecAttrAccount as String: identity.account,
            kSecAttrAccessGroup as String: identity.accessGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
    }

    static func decode(status: OSStatus, result: CFTypeRef?) -> RecoveryKeychainRead {
        guard status == errSecSuccess, let attributes = result as? [String: Any] else {
            return RecoveryKeychainRead(status: status)
        }
        return RecoveryKeychainRead(
            status: status,
            bytes: attributes[kSecValueData as String] as? Data,
            service: attributes[kSecAttrService as String] as? String,
            account: attributes[kSecAttrAccount as String] as? String,
            accessGroup: attributes[kSecAttrAccessGroup as String] as? String,
            accessibility: attributes[kSecAttrAccessible as String] as? String,
            synchronizable: attributes[kSecAttrSynchronizable as String] as? Bool
        )
    }
}

/// Production load-only installation-key provider. Security calls execute on this
/// actor rather than the main actor. Nothing is cached: each checkpoint respects
/// the current Keychain access policy. No missing/error path provisions a key.
public actor KeychainRecoveryKey: RecoveryKeyProviding {
    private let identity: RecoveryKeychainIdentity
    private let reader: any RecoveryKeychainReading

    public init(identity: RecoveryKeychainIdentity) {
        self.identity = identity; self.reader = SystemRecoveryKeychainReader()
    }

    init(identity: RecoveryKeychainIdentity, reader: any RecoveryKeychainReading) {
        self.identity = identity; self.reader = reader
    }

    public func loadRecoveryKey() async throws -> SymmetricKey {
        try Task.checkCancellation()
        let result = reader.copyMatching(identity)
        try Task.checkCancellation()
        switch result.status {
        case errSecSuccess: break
        case errSecItemNotFound: throw RecoveryKeyError.missing
        case errSecAuthFailed, errSecUserCanceled:
            throw RecoveryKeyError.denied("Access to the recovery key was denied or cancelled.")
        case errSecInteractionNotAllowed, errSecInteractionRequired:
            // Security does not distinguish device lock from required interaction.
            throw RecoveryKeyError.locked("The recovery key is locked or requires authentication. Unlock and retry.")
        case errSecMissingEntitlement:
            throw RecoveryKeyError.unavailable("The application's signing configuration does not permit recovery key access.")
        case errSecDecode:
            throw RecoveryKeyError.unavailable("The recovery key item is malformed. Existing recovery data was preserved.")
        default:
            throw RecoveryKeyError.unavailable("The recovery key is unavailable. Existing recovery data was preserved.")
        }
        guard result.service == identity.service, result.account == identity.account,
              result.accessGroup == identity.accessGroup,
              result.accessibility == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
              result.synchronizable == false else {
            throw RecoveryKeyError.unavailable("The recovery key item does not have the required identity or protection policy.")
        }
        guard let bytes = result.bytes, bytes.count == 32 else {
            throw RecoveryKeyError.unavailable("The recovery key item is malformed. Existing recovery data was preserved.")
        }
        return SymmetricKey(data: bytes)
    }
}
