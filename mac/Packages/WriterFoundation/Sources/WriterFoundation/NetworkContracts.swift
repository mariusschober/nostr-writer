import Foundation
import Darwin

// MARK: - Relay URL normalization

/// Configuration that decides which relay transports a build will accept.
///
/// Normalization itself is identical in every configuration. The only
/// difference is whether plaintext `ws` to an actual loopback host is allowed.
public struct RelayURLConfiguration: Hashable, Sendable {

    /// Whether `ws://` may be used with a loopback host. Default `false`.
    ///
    /// The product contract permits unencrypted loopback sockets only in test
    /// and developer configuration, so production must leave this off.
    public let allowInsecureLoopback: Bool

    public init(allowInsecureLoopback: Bool = false) {
        self.allowInsecureLoopback = allowInsecureLoopback
    }

    /// Shipping configuration: `wss` only.
    public static let production = RelayURLConfiguration(allowInsecureLoopback: false)

    /// Developer/testing configuration: also allows `ws` on loopback.
    public static let developer = RelayURLConfiguration(allowInsecureLoopback: true)
}

/// Typed failures from relay URL normalization.
public enum RelayURLError: Error, Equatable, Sendable {

    /// The input was empty or contained only whitespace.
    case empty
    /// A control character or an encoding-required character appeared at `byteOffset`.
    case invalidCharacter(byteOffset: Int)
    /// No `scheme://` prefix was present.
    case missingScheme
    /// The scheme is not the WebSocket `ws` or `wss`.
    case unsupportedScheme(String)
    /// The authority contained no host.
    case missingHost
    /// A `user:password@` style userinfo component was present.
    case userinfoNotAllowed
    /// A `#` fragment was present.
    case fragmentNotAllowed
    /// The host contained a percent escape or an otherwise invalid character.
    case invalidHost(String)
    /// The port text could not be read as a decimal number.
    case invalidPort(String)
    /// The port was outside `1...65535`. Carries the original text.
    case portOutOfRange(String)
    /// A `%` at `byteOffset` was not followed by two hexadecimal digits.
    case invalidPercentEscape(byteOffset: Int)
    /// Plaintext `ws` was requested for a host that is not loopback.
    case insecureRemoteWebSocket(String)
    /// Plaintext `ws` on a loopback host without the explicit developer opt-in.
    case insecureLoopbackNotPermitted(String)
}

extension RelayURLError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a relay address."
        case .invalidCharacter(let byteOffset):
            return "The relay address contains a character that must be percent-encoded (offset \(byteOffset))."
        case .missingScheme:
            return "The relay address must begin with wss:// (or ws:// in development)."
        case .unsupportedScheme(let scheme):
            return "Relay scheme \(scheme) is not supported; use wss."
        case .missingHost:
            return "The relay address has no host."
        case .userinfoNotAllowed:
            return "Credentials in a relay address are not supported."
        case .fragmentNotAllowed:
            return "A relay address cannot contain a fragment."
        case .invalidHost(let host):
            return "The relay host \(host) is not valid."
        case .invalidPort(let text):
            return "The relay port \(text) is not a number."
        case .portOutOfRange(let text):
            return "The relay port \(text) is outside 1-65535."
        case .invalidPercentEscape(let byteOffset):
            return "The relay address has an invalid percent escape at offset \(byteOffset)."
        case .insecureRemoteWebSocket(let host):
            return "ws:// is not allowed for the remote host \(host); use wss://."
        case .insecureLoopbackNotPermitted(let host):
            return "ws:// on \(host) is only available in developer configuration."
        }
    }
}

/// A normalized relay identity.
///
/// Normalization is deliberately narrow so that two different relays never
/// collapse into one identity, and one relay never splits into two. Only the
/// scheme and host case and the default port are normalized, per the NOSTR
/// contract. The path and query are preserved byte for byte, including the case
/// of percent escapes, because a relay may serve different content per path and
/// per query.
public struct RelayURL: Hashable, Sendable, CustomStringConvertible {

    /// Lowercased scheme: `wss`, or `ws` in developer configuration.
    public let scheme: String

    /// Lowercased host. IPv6 literals retain their surrounding brackets.
    public let host: String

    /// Explicit port, or `nil` when the address uses the scheme default.
    public let port: Int?

    /// Exact path, or `""` for the root. Always either empty or starting with `/`.
    public let path: String

    /// Exact query without the leading `?`, or `nil` when there was no `?`.
    public let query: String?

    private init(scheme: String, host: String, port: Int?, path: String, query: String?) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.query = query
    }

    /// The default port for a scheme, or `nil` for a scheme we do not accept.
    public static func defaultPort(forScheme scheme: String) -> Int? {
        switch scheme {
        case "wss": return 443
        case "ws": return 80
        default: return nil
        }
    }

    /// Canonical text form. Two relay addresses are the same relay exactly when
    /// their `description` values match.
    public var description: String {
        var text = scheme + "://" + host
        if let port { text += ":" + String(port) }
        text += path
        if let query { text += "?" + query }
        return text
    }

    /// Rebuilds a `URL` from the canonical form.
    public func asURL() throws -> URL {
        guard let url = URL(string: description) else {
            throw RelayURLError.invalidHost(host)
        }
        return url
    }

    /// Host with IPv6 brackets removed, for comparison and display.
    public var bareHost: String {
        if host.hasPrefix("["), host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    /// Whether the host is an actual loopback address.
    public var isLoopback: Bool {
        RelayURL.loopbackHosts.contains(bareHost) || RelayURL.isIPv4Loopback(bareHost)
    }

    private static let loopbackHosts: Set<String> = [
        "localhost",
        "::1",
        "0:0:0:0:0:0:0:1",
    ]

    /// Whole `127.0.0.0/8` is loopback per RFC 1122.
    private static func isIPv4Loopback(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "127" else { return false }
        for part in parts {
            guard let octet = Int(part), octet >= 0, octet <= 255,
                  String(octet) == part else { return false }
        }
        return true
    }

    /// Normalizes a user-entered relay address.
    ///
    /// Rejected inputs: empty or whitespace input, control characters,
    /// encoding-required characters, a missing or non-WebSocket scheme,
    /// userinfo, fragments, an empty host, invalid ports, invalid percent
    /// escapes, remote `ws`, and loopback `ws` without the developer opt-in.
    public init(
        normalizing raw: String,
        configuration: RelayURLConfiguration = .production
    ) throws {
        guard !raw.isEmpty, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayURLError.empty
        }

        let bytes = Array(raw.utf8)
        for (offset, byte) in bytes.enumerated() {
            guard byte >= 0x21, byte <= 0x7E,
                  !RelayURL.encodingRequiredCharacters.contains(byte) else {
                throw RelayURLError.invalidCharacter(byteOffset: offset)
            }
        }

        // All offsets below are absolute byte offsets into `raw`, so reported
        // positions are unambiguous regardless of which component failed.
        guard let separator = RelayURL.firstIndex(of: RelayURL.schemeSeparator, in: bytes, from: 0) else {
            throw RelayURLError.missingScheme
        }
        let schemeText = String(decoding: bytes[0..<separator], as: UTF8.self)
        guard !schemeText.isEmpty else { throw RelayURLError.missingScheme }
        let scheme = schemeText.lowercased()
        guard RelayURL.defaultPort(forScheme: scheme) != nil else {
            throw RelayURLError.unsupportedScheme(scheme)
        }

        let afterScheme = separator + RelayURL.schemeSeparator.count
        if bytes[afterScheme...].firstIndex(of: 0x23) != nil {
            throw RelayURLError.fragmentNotAllowed
        }

        var authorityEnd = bytes.count
        var index = afterScheme
        while index < bytes.count {
            if bytes[index] == 0x2F || bytes[index] == 0x3F {
                authorityEnd = index
                break
            }
            index += 1
        }

        let authority = bytes[afterScheme..<authorityEnd]
        guard !authority.contains(0x40) else { throw RelayURLError.userinfoNotAllowed }

        let (hostText, portText) = try RelayURL.splitAuthority(authority)
        let host = hostText.lowercased()
        guard !host.isEmpty else { throw RelayURLError.missingHost }
        guard !host.contains("%") else { throw RelayURLError.invalidHost(host) }
        try RelayURL.validateHost(host)

        var port: Int?
        if let portText {
            guard !portText.isEmpty else { throw RelayURLError.invalidPort(portText) }
            guard portText.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw RelayURLError.invalidPort(portText)
            }
            guard let parsed = Int(portText), parsed >= 1, parsed <= 65535 else {
                throw RelayURLError.portOutOfRange(portText)
            }
            port = parsed == RelayURL.defaultPort(forScheme: scheme) ? nil : parsed
        }

        var pathRange = authorityEnd..<authorityEnd
        var queryRange: Range<Int>?
        if authorityEnd < bytes.count {
            if bytes[authorityEnd] == 0x3F {
                queryRange = (authorityEnd + 1)..<bytes.count
            } else {
                let queryMark = bytes[authorityEnd...].firstIndex(of: 0x3F) ?? bytes.count
                pathRange = authorityEnd..<queryMark
                if queryMark < bytes.count {
                    queryRange = (queryMark + 1)..<bytes.count
                }
            }
        }

        // Root semantics: "/" is the same relay as no path at all. The path and
        // query themselves keep their exact bytes, including escape case.
        let pathText = String(decoding: bytes[pathRange], as: UTF8.self)
        let path = pathText == "/" ? "" : pathText
        let query = queryRange.map { String(decoding: bytes[$0], as: UTF8.self) }

        try RelayURL.validatePercentEscapes(bytes, in: pathRange)
        if let queryRange { try RelayURL.validatePercentEscapes(bytes, in: queryRange) }

        if scheme == "ws" {
            guard RelayURL.isLoopbackHost(host) else {
                throw RelayURLError.insecureRemoteWebSocket(host)
            }
            guard configuration.allowInsecureLoopback else {
                throw RelayURLError.insecureLoopbackNotPermitted(host)
            }
        }

        self.init(scheme: scheme, host: host, port: port, path: path, query: query)
    }

    /// Characters that RFC 3986 requires to be percent-encoded.
    private static let encodingRequiredCharacters: Set<UInt8> = [
        0x20, 0x22, 0x3C, 0x3E, 0x5C, 0x5E, 0x60, 0x7B, 0x7C, 0x7D,
    ]

    private static let schemeSeparator: [UInt8] = [0x3A, 0x2F, 0x2F]  // "://"

    private static func isLoopbackHost(_ host: String) -> Bool {
        let bare = stripBrackets(host)
        return loopbackHosts.contains(bare) || isIPv4Loopback(bare)
    }

    private static func stripBrackets(_ host: String) -> String {
        if host.hasPrefix("["), host.hasSuffix("]") {
            return String(host.dropFirst().dropLast())
        }
        return host
    }

    private static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// Splits `host`, `host:port` or `[v6]:port`, returning the port text if present.
    private static func splitAuthority(
        _ authority: ArraySlice<UInt8>
    ) throws -> (host: String, port: String?) {
        let bytes = Array(authority)
        if bytes.first == 0x5B {  // "["
            guard let closing = bytes.firstIndex(of: 0x5D) else {
                throw RelayURLError.invalidHost(ascii(authority))
            }
            let host = ascii(bytes[0...closing])
            let tail = bytes[(closing + 1)...]
            if tail.isEmpty { return (host, nil) }
            guard tail.first == 0x3A else {
                throw RelayURLError.invalidHost(ascii(authority))
            }
            return (host, ascii(tail.dropFirst()))
        }
        guard let colon = bytes.firstIndex(of: 0x3A) else {
            return (ascii(authority), nil)
        }
        let host = ascii(bytes[0..<colon])
        let port = ascii(bytes[(colon + 1)...])
        // A second colon means an unbracketed IPv6 literal, which is not a host.
        guard !port.contains(":") else { throw RelayURLError.invalidHost(ascii(authority)) }
        return (host, port)
    }

    private static func validateHost(_ host: String) throws {
        let bare = stripBrackets(host)
        guard !bare.isEmpty else { throw RelayURLError.missingHost }
        if host.hasPrefix("[") {
            var address = in6_addr()
            guard host.hasSuffix("]"), bare.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
                throw RelayURLError.invalidHost(host)
            }
            return
        }
        guard !bare.hasPrefix("."), !bare.hasSuffix("."), !bare.contains("..") else {
            throw RelayURLError.invalidHost(host)
        }
        guard bare.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == ":" || $0 == "_") }) else {
            throw RelayURLError.invalidHost(host)
        }
    }

    /// Validates `%` escapes inside an absolute byte range of the original input.
    private static func validatePercentEscapes(_ bytes: [UInt8], in range: Range<Int>) throws {
        var index = range.lowerBound
        while index < range.upperBound {
            if bytes[index] == 0x25 {
                guard index + 2 < range.upperBound,
                      isHexDigit(bytes[index + 1]),
                      isHexDigit(bytes[index + 2]) else {
                    throw RelayURLError.invalidPercentEscape(byteOffset: index)
                }
                index += 3
            } else {
                index += 1
            }
        }
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39)
            || (byte >= 0x41 && byte <= 0x46)
            || (byte >= 0x61 && byte <= 0x66)
    }

    private static func firstIndex(
        of pattern: [UInt8],
        in bytes: [UInt8],
        from start: Int
    ) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        let lastCandidate = bytes.count - pattern.count
        guard start <= lastCandidate else { return nil }
        for candidate in start...lastCandidate {
            if bytes[candidate..<(candidate + pattern.count)].elementsEqual(pattern) {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - NIP-44 v2 length arithmetic

/// Typed failures from NIP-44 v2 framing arithmetic.
///
/// These are framing errors only. Nothing here encrypts or decrypts, and no
/// error in this type is evidence about the content of any message.
public enum NIP44LengthError: Error, Equatable, Sendable {

    /// NIP-44 v2 requires at least one plaintext byte.
    case emptyPlaintext
    /// The plaintext exceeded the 2^32-1 theoretical ceiling.
    case plaintextAboveTheoreticalMaximum(UInt64)
    /// The plaintext exceeded the caller's application cap.
    case plaintextAboveApplicationCap(bytes: UInt64, cap: UInt64)
    /// The encoded payload would exceed the caller's outer wire cap.
    case payloadAboveWireCap(encodedCharacters: UInt64, cap: UInt64)
    /// A size computation would exceed `UInt64`.
    case lengthArithmeticOverflow(UInt64)
    /// The supplied bytes were not a complete or well-formed length prefix.
    case malformedLengthPrefix
    /// A 6-byte extended prefix encoded a length below the 65536 threshold,
    /// which the spec defines as invalid padding.
    case nonCanonicalExtendedPrefix(UInt64)
}

extension NIP44LengthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyPlaintext:
            return "NIP-44 payloads must contain at least one byte."
        case .plaintextAboveTheoreticalMaximum(let bytes):
            return "NIP-44 plaintext of \(bytes) bytes exceeds the theoretical maximum."
        case .plaintextAboveApplicationCap(let bytes, let cap):
            return "Draft payload of \(bytes) bytes exceeds this app's \(cap)-byte limit."
        case .payloadAboveWireCap(let characters, let cap):
            return "Encoded payload of \(characters) characters exceeds the \(cap)-character relay limit."
        case .lengthArithmeticOverflow(let bytes):
            return "NIP-44 framing for \(bytes) bytes exceeds the supported size."
        case .malformedLengthPrefix:
            return "The NIP-44 length prefix is incomplete or malformed."
        case .nonCanonicalExtendedPrefix(let length):
            return "A NIP-44 extended prefix of \(length) bytes is below the 65536 threshold."
        }
    }
}

/// Limits applied on top of the NIP-44 theoretical ceiling.
///
/// The application plaintext cap and the outer wire cap are deliberately
/// separate: the first bounds the unsigned draft JSON this app will encrypt,
/// the second bounds what may be put on a relay socket.
public struct NIP44Limits: Hashable, Sendable {

    /// Maximum plaintext byte count accepted for a draft. Default 1 MiB.
    public let applicationPlaintextCap: UInt64

    /// Maximum encoded (Base64) payload length accepted. Default 2 MiB.
    public let outerWireCap: UInt64

    public init(applicationPlaintextCap: UInt64 = NIP44Limits.defaultPlaintextCap,
                outerWireCap: UInt64 = NIP44Limits.defaultWireCap) {
        self.applicationPlaintextCap = applicationPlaintextCap
        self.outerWireCap = outerWireCap
    }

    /// 1 MiB, the app's unsigned draft JSON ceiling.
    public static let defaultPlaintextCap: UInt64 = 1 << 20

    /// 2 MiB, the relay message ceiling.
    public static let defaultWireCap: UInt64 = 2 << 20

    public static let standard = NIP44Limits()
}

/// Exact byte accounting for one NIP-44 v2 payload.
///
/// Field meanings follow the pinned specification's own summary:
/// `metadata` is always 65 bytes (version, nonce, MAC); the plaintext length
/// prefix is 2 bytes below 65536 and 6 bytes at or above it; the padded
/// plaintext is `calc_padded_len(plaintext)` and may itself reach 2^32.
public struct NIP44Framing: Hashable, Sendable {

    /// Original plaintext byte count as supplied.
    public let plaintextByteCount: UInt64

    /// `calc_padded_len(plaintext)`, excluding the length prefix.
    public let paddedPlaintextByteCount: UInt64

    /// Length prefix size: 2 bytes below 65536, 6 bytes at or above it.
    public let lengthPrefixByteCount: Int

    /// Encrypted region: length prefix plus padded plaintext.
    public let ciphertextByteCount: UInt64

    /// Full raw payload: 65 bytes of metadata plus the ciphertext.
    public let payloadByteCount: UInt64

    /// Padded Base64 length of the full payload.
    public let base64CharacterCount: UInt64

    /// Whether this payload uses the extended length prefix.
    public var usesExtendedPrefix: Bool { lengthPrefixByteCount == 6 }
}

/// Checked NIP-44 v2 padding and framing arithmetic.
///
/// Sizes only: no cipher, no key handling and no padding content. Zero padding
/// bytes belong to the Stage 06 implementation.
public enum NIP44Lengths {

    /// 65 bytes: version, nonce and MAC, excluding the length prefix.
    public static let metadataByteCount: UInt64 = 65

    /// 2^32-1, the maximum plaintext length the spec permits.
    public static let theoreticalMaximumPlaintextByteCount: UInt64 = (1 << 32) - 1

    /// Plaintext length at which the 6-byte extended prefix becomes mandatory.
    public static let extendedPrefixThreshold: UInt64 = 1 << 16

    // MARK: Padding

    /// `calc_padded_len` for a plaintext byte count.
    ///
    /// Round up to 32-byte chunks, or to `nextPowerOfTwo / 8` chunks once the
    /// next power of two exceeds 256. For a plaintext of 2^32-1 this returns
    /// 2^32, which is why the arithmetic is 64-bit.
    public static func paddedLength(of plaintextByteCount: UInt64) throws -> UInt64 {
        guard plaintextByteCount > 0 else { throw NIP44LengthError.emptyPlaintext }
        guard plaintextByteCount <= theoreticalMaximumPlaintextByteCount else {
            throw NIP44LengthError.plaintextAboveTheoreticalMaximum(plaintextByteCount)
        }
        if plaintextByteCount <= 32 { return 32 }
        let nextPower = smallestPowerOfTwo(atLeast: plaintextByteCount)
        let chunk: UInt64 = nextPower <= 256 ? 32 : nextPower / 8
        let (adjusted, subtractOverflow) = plaintextByteCount.subtractingReportingOverflow(1)
        guard !subtractOverflow else {
            throw NIP44LengthError.lengthArithmeticOverflow(plaintextByteCount)
        }
        let (quotient, _) = adjusted.quotientAndRemainder(dividingBy: chunk)
        let (chunks, overflow) = quotient.addingReportingOverflow(1)
        guard !overflow else {
            throw NIP44LengthError.lengthArithmeticOverflow(plaintextByteCount)
        }
        let (padded, multiplyOverflow) = chunk.multipliedReportingOverflow(by: chunks)
        guard !multiplyOverflow else {
            throw NIP44LengthError.lengthArithmeticOverflow(plaintextByteCount)
        }
        return padded
    }

    /// Smallest power of two greater than or equal to `value`. `value` must be positive.
    private static func smallestPowerOfTwo(atLeast value: UInt64) -> UInt64 {
        precondition(value > 0, "value must be positive")
        precondition(value <= theoreticalMaximumPlaintextByteCount)
        var power: UInt64 = 1
        while power < value { power <<= 1 }
        return power
    }

    // MARK: Framing

    /// Length prefix size, chosen from the *plaintext* length.
    ///
    /// The spec encodes the original plaintext length in the prefix, so the
    /// threshold is applied to that value and not to the padded length.
    public static func lengthPrefixByteCount(forPlaintextLength plaintextLength: UInt64) throws -> Int {
        guard plaintextLength > 0 else { throw NIP44LengthError.emptyPlaintext }
        guard plaintextLength <= theoreticalMaximumPlaintextByteCount else {
            throw NIP44LengthError.plaintextAboveTheoreticalMaximum(plaintextLength)
        }
        return plaintextLength >= extendedPrefixThreshold ? 6 : 2
    }

    /// Padded Base64 length for a byte count, including `=` padding characters.
    ///
    /// Reports overflow instead of trapping, so a hostile size cannot crash a
    /// caller that is still validating its input.
    public static func base64CharacterCount(forByteCount byteCount: UInt64) throws -> UInt64 {
        let (adjusted, addOverflow) = byteCount.addingReportingOverflow(2)
        guard !addOverflow else { throw NIP44LengthError.lengthArithmeticOverflow(byteCount) }
        let (groups, _) = adjusted.quotientAndRemainder(dividingBy: 3)
        let (characters, multiplyOverflow) = groups.multipliedReportingOverflow(by: 4)
        guard !multiplyOverflow else { throw NIP44LengthError.lengthArithmeticOverflow(byteCount) }
        return characters
    }

    /// Full byte accounting for one payload, with both caps enforced before any
    /// buffer is allocated.
    public static func framing(
        plaintextByteCount: UInt64,
        limits: NIP44Limits = .standard
    ) throws -> NIP44Framing {
        guard plaintextByteCount > 0 else { throw NIP44LengthError.emptyPlaintext }
        guard plaintextByteCount <= theoreticalMaximumPlaintextByteCount else {
            throw NIP44LengthError.plaintextAboveTheoreticalMaximum(plaintextByteCount)
        }
        guard plaintextByteCount <= limits.applicationPlaintextCap else {
            throw NIP44LengthError.plaintextAboveApplicationCap(
                bytes: plaintextByteCount,
                cap: limits.applicationPlaintextCap
            )
        }

        let prefix = try lengthPrefixByteCount(forPlaintextLength: plaintextByteCount)
        let padded = try paddedLength(of: plaintextByteCount)
        let (ciphertext, ciphertextOverflow) = UInt64(prefix).addingReportingOverflow(padded)
        guard !ciphertextOverflow else {
            throw NIP44LengthError.lengthArithmeticOverflow(plaintextByteCount)
        }
        let (payload, payloadOverflow) = metadataByteCount.addingReportingOverflow(ciphertext)
        guard !payloadOverflow else {
            throw NIP44LengthError.lengthArithmeticOverflow(plaintextByteCount)
        }
        let base64 = try base64CharacterCount(forByteCount: payload)

        guard base64 <= limits.outerWireCap else {
            throw NIP44LengthError.payloadAboveWireCap(
                encodedCharacters: base64,
                cap: limits.outerWireCap
            )
        }

        return NIP44Framing(
            plaintextByteCount: plaintextByteCount,
            paddedPlaintextByteCount: padded,
            lengthPrefixByteCount: prefix,
            ciphertextByteCount: ciphertext,
            payloadByteCount: payload,
            base64CharacterCount: base64
        )
    }

    // MARK: Length prefix codec

    /// Encodes the original plaintext length as the big-endian length prefix.
    ///
    /// Emits the 2-byte form below 65536 and the 6-byte form at or above it:
    /// `[0x00, 0x00][length: u32]`. The extended form is never emitted for a
    /// shorter message.
    public static func encodeLengthPrefix(plaintextLength: UInt64) throws -> [UInt8] {
        let count = try lengthPrefixByteCount(forPlaintextLength: plaintextLength)
        if count == 2 {
            return [UInt8(plaintextLength >> 8), UInt8(plaintextLength & 0xFF)]
        }
        return [
            0x00, 0x00,
            UInt8((plaintextLength >> 24) & 0xFF),
            UInt8((plaintextLength >> 16) & 0xFF),
            UInt8((plaintextLength >> 8) & 0xFF),
            UInt8(plaintextLength & 0xFF),
        ]
    }

    /// Reads a NIP-44 length prefix, returning its size and the plaintext length.
    ///
    /// A leading zero u16 selects the extended form and must then encode a value
    /// of at least 65536, exactly as the spec's `unpad` requires.
    public static func decodeLengthPrefix(
        _ bytes: ArraySlice<UInt8>
    ) throws -> (prefixByteCount: Int, plaintextLength: UInt64) {
        guard bytes.count >= 2 else { throw NIP44LengthError.malformedLengthPrefix }
        let first = bytes[bytes.startIndex]
        let second = bytes[bytes.startIndex + 1]
        if first != 0 || second != 0 {
            return (2, (UInt64(first) << 8) | UInt64(second))
        }
        guard bytes.count >= 6 else { throw NIP44LengthError.malformedLengthPrefix }
        var value: UInt64 = 0
        for offset in 2..<6 {
            value = (value << 8) | UInt64(bytes[bytes.startIndex + offset])
        }
        guard value >= extendedPrefixThreshold else {
            throw NIP44LengthError.nonCanonicalExtendedPrefix(value)
        }
        return (6, value)
    }
}

// MARK: - Replaceable event ordering

/// A 32-byte NIP-01 event id.
public struct EventID: Hashable, Sendable, CustomStringConvertible {

    /// Exactly 32 bytes.
    public let bytes: [UInt8]

    /// Validates the exact 32-byte length.
    public init(bytes: [UInt8]) throws {
        guard bytes.count == 32 else {
            throw ReplaceableOrderingError.invalidEventIDLength(bytes.count)
        }
        self.bytes = bytes
    }

    /// Validates 64 lowercase hexadecimal characters.
    public init(hex: String) throws {
        let characters = Array(hex)
        guard characters.count == 64 else {
            throw ReplaceableOrderingError.invalidEventIDLength(characters.count)
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var index = 0
        while index < characters.count {
            guard let high = EventID.hexValue(characters[index]),
                  let low = EventID.hexValue(characters[index + 1]) else {
                throw ReplaceableOrderingError.invalidEventIDText(hex)
            }
            bytes.append((high << 4) | low)
            index += 2
        }
        self.bytes = bytes
    }

    /// Lowercase hexadecimal rendering.
    public var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String { hex }

    /// Unsigned byte order, which matches lowercase hexadecimal lexical order.
    private static func hexValue(_ character: Character) -> UInt8? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case 0x30...0x39: return ascii - 0x30
        case 0x61...0x66: return ascii - 0x61 + 10
        case 0x41...0x46: return ascii - 0x41 + 10
        default: return nil
        }
    }
}

/// The identity under which a replaceable event competes.
///
/// NIP-01 kinds 0 and 3 compete per author; kinds 10000-19999 compete per
/// author; kinds 30000-39999 (addressable) compete per author and `d` tag.
public struct ReplaceableAddress: Hashable, Sendable {

    /// NIP-01 event kind.
    public let kind: Int
    /// 32-byte author public key.
    public let pubkey: [UInt8]
    /// The `d` tag value for addressable kinds; `nil` otherwise.
    public let dTag: String?

    /// Whether `kind` is replaceable, and whether it must carry a `d` tag.
    public static func classification(of kind: Int) -> (replaceable: Bool, addressable: Bool) {
        if kind == 0 || kind == 3 { return (true, false) }
        if (10000..<20000).contains(kind) { return (true, false) }
        if (30000..<40000).contains(kind) { return (true, true) }
        return (false, false)
    }

    public init(kind: Int, pubkey: [UInt8], dTag: String? = nil) throws {
        let classification = ReplaceableAddress.classification(of: kind)
        guard classification.replaceable else {
            throw ReplaceableOrderingError.notReplaceable(kind: kind)
        }
        guard pubkey.count == 32 else {
            throw ReplaceableOrderingError.invalidPubkeyLength(pubkey.count)
        }
        if classification.addressable {
            guard dTag != nil else {
                throw ReplaceableOrderingError.missingDTag(kind: kind)
            }
        } else {
            guard dTag == nil else {
                throw ReplaceableOrderingError.unexpectedDTag(kind: kind)
            }
        }
        self.kind = kind
        self.pubkey = pubkey
        self.dTag = dTag
    }
}

/// An event that may compete for a replaceable address.
///
/// Construction of this value asserts that the caller already verified the
/// event: its computed NIP-01 id equals `eventID` and its BIP-340 signature is
/// valid. Ordering unscreened relay input with this type would let an
/// unauthenticated event win, so verification always happens first.
public struct VerifiedReplaceableEvent: Hashable, Sendable {

    /// Address this event competes for.
    public let address: ReplaceableAddress
    /// Signed Unix timestamp.
    public let createdAt: Int64
    /// Verified event id, which breaks ties.
    public let eventID: EventID
    /// Optional NIP-40 expiration, in Unix seconds.
    public let expiration: Int64?

    public init(
        address: ReplaceableAddress,
        createdAt: Int64,
        eventID: EventID,
        expiration: Int64? = nil
    ) {
        self.address = address
        self.createdAt = createdAt
        self.eventID = eventID
        self.expiration = expiration
    }

    /// Whether NIP-40 says this event has expired at `now`.
    public func isExpired(at now: Int64) -> Bool {
        guard let expiration else { return false }
        return expiration <= now
    }
}

/// Typed failures from replaceable ordering.
public enum ReplaceableOrderingError: Error, Equatable, Sendable {
    /// An event id was not 32 bytes.
    case invalidEventIDLength(Int)
    /// An event id contained a character that is not hexadecimal.
    case invalidEventIDText(String)
    /// An author public key was not 32 bytes.
    case invalidPubkeyLength(Int)
    /// The kind is not replaceable under NIP-01.
    case notReplaceable(kind: Int)
    /// An addressable kind did not supply its `d` tag.
    case missingDTag(kind: Int)
    /// A non-addressable kind supplied a `d` tag.
    case unexpectedDTag(kind: Int)
    /// Two events from different addresses were compared.
    case addressMismatch
}

extension ReplaceableOrderingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEventIDLength(let count):
            return "An event id must be 32 bytes, not \(count)."
        case .invalidEventIDText:
            return "An event id must be 64 hexadecimal characters."
        case .invalidPubkeyLength(let count):
            return "An author public key must be 32 bytes, not \(count)."
        case .notReplaceable(let kind):
            return "Kind \(kind) is not a replaceable event kind."
        case .missingDTag(let kind):
            return "Addressable kind \(kind) requires a d tag."
        case .unexpectedDTag(let kind):
            return "Kind \(kind) must not carry a d tag."
        case .addressMismatch:
            return "Events from different addresses cannot replace each other."
        }
    }
}

/// NIP-01 replacement resolution.
///
/// The winner is the highest `created_at`, and among equal timestamps the
/// lowest event id. This chooses between versions a relay already resolved; it
/// is never permission to overwrite a local unsent draft, which requires an
/// explicit Keep Both decision in the UI.
public enum ReplaceableOrdering {

    /// Whether `candidate` wins over `incumbent` under NIP-01.
    ///
    /// Both events must belong to the same address, and both must already have
    /// passed signature verification. Equal ids never replace.
    public static func supersedes(
        _ candidate: VerifiedReplaceableEvent,
        _ incumbent: VerifiedReplaceableEvent
    ) throws -> Bool {
        guard candidate.address == incumbent.address else {
            throw ReplaceableOrderingError.addressMismatch
        }
        if candidate.eventID == incumbent.eventID { return false }
        if candidate.createdAt != incumbent.createdAt {
            return candidate.createdAt > incumbent.createdAt
        }
        return candidate.eventID.bytes.lexicographicallyPrecedes(incumbent.eventID.bytes)
    }

    /// Winner among events for one address.
    ///
    /// The first event's address anchors the comparison; events for any other
    /// address are ignored rather than allowed to overwrite it. When `now` is
    /// supplied, expired events are skipped. Returns `nil` for an empty list or
    /// a list emptied by expiration.
    public static func winner(
        of events: [VerifiedReplaceableEvent],
        at now: Int64? = nil
    ) -> VerifiedReplaceableEvent? {
        guard let anchor = events.first?.address else { return nil }
        var best: VerifiedReplaceableEvent?
        for event in events {
            guard event.address == anchor else { continue }
            if let now, event.isExpired(at: now) { continue }
            guard let current = best else {
                best = event
                continue
            }
            if (try? supersedes(event, current)) == true {
                best = event
            }
        }
        return best
    }

    /// Winner per address across a mixed event list.
    public static func resolve(
        _ events: [VerifiedReplaceableEvent],
        at now: Int64? = nil
    ) -> [ReplaceableAddress: VerifiedReplaceableEvent] {
        var grouped: [ReplaceableAddress: [VerifiedReplaceableEvent]] = [:]
        for event in events {
            grouped[event.address, default: []].append(event)
        }
        var winners: [ReplaceableAddress: VerifiedReplaceableEvent] = [:]
        for (address, group) in grouped {
            winners[address] = winner(of: group, at: now)
        }
        return winners
    }
}
