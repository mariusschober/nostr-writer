import XCTest
@testable import WriterFoundation

final class RelayHostAdversarialTests: XCTestCase {
    func testMalformedIPv6AndAmbiguousIPv4AreRejectedBeforeNetworkUse() {
        for raw in ["wss://[not:ipv6]", "wss://[1:2:3]", "wss://[:::1]",
                    "ws://000127.0.0.1", "ws://127.01.0.1"] {
            XCTAssertThrowsError(try RelayURL(normalizing: raw, configuration: .developer), raw)
        }
        XCTAssertNoThrow(try RelayURL(normalizing: "ws://[::1]:8080", configuration: .developer))
        XCTAssertNoThrow(try RelayURL(normalizing: "ws://127.0.0.1:8080", configuration: .developer))
    }
}

// MARK: - Helpers

private func relay(
    _ text: String,
    configuration: RelayURLConfiguration = .production
) -> RelayURL? {
    try? RelayURL(normalizing: text, configuration: configuration)
}

private func canonical(
    _ text: String,
    configuration: RelayURLConfiguration = .production
) -> String? {
    relay(text, configuration: configuration)?.description
}

private func relayError(
    _ text: String,
    configuration: RelayURLConfiguration = .production
) -> RelayURLError? {
    do {
        _ = try RelayURL(normalizing: text, configuration: configuration)
        return nil
    } catch let error as RelayURLError {
        return error
    } catch {
        return nil
    }
}

private func framing(_ plaintextByteCount: UInt64,
                     limits: NIP44Limits = .standard) -> NIP44Framing? {
    try? NIP44Lengths.framing(plaintextByteCount: plaintextByteCount, limits: limits)
}

private func framingError(_ plaintextByteCount: UInt64,
                          limits: NIP44Limits = .standard) -> NIP44LengthError? {
    do {
        _ = try NIP44Lengths.framing(plaintextByteCount: plaintextByteCount, limits: limits)
        return nil
    } catch let error as NIP44LengthError {
        return error
    } catch {
        return nil
    }
}

private func addressError(kind: Int, pubkey: [UInt8],
                          dTag: String?) -> ReplaceableOrderingError? {
    do {
        _ = try ReplaceableAddress(kind: kind, pubkey: pubkey, dTag: dTag)
        return nil
    } catch let error as ReplaceableOrderingError {
        return error
    } catch {
        return nil
    }
}

private let pubkeyA = [UInt8](repeating: 0x11, count: 32)
private let pubkeyB = [UInt8](repeating: 0x22, count: 32)

private func id(_ byte: UInt8) throws -> EventID {
    try EventID(bytes: [UInt8](repeating: byte, count: 32))
}

// MARK: - Relay URL normalization

final class RelayURLTests: XCTestCase {

    func testBasicNormalization() {
        XCTAssertEqual(canonical("wss://relay.example.com"), "wss://relay.example.com")
        XCTAssertEqual(canonical("wss://relay.example.com/path"), "wss://relay.example.com/path")
    }

    func testSchemeAndHostCaseAreNormalized() {
        XCTAssertEqual(canonical("WSS://Relay.Example.COM"), "wss://relay.example.com")
        XCTAssertEqual(canonical("wss://RELAY.EXAMPLE.COM/a"), "wss://relay.example.com/a")
        XCTAssertEqual(relay("WSS://Relay.Example.COM"), relay("wss://relay.example.com"))
    }

    func testDefaultPortsAreDroppedAndNonDefaultPortsKept() {
        XCTAssertEqual(canonical("wss://relay.example.com:443"), "wss://relay.example.com")
        XCTAssertEqual(canonical("wss://relay.example.com:8443"), "wss://relay.example.com:8443")
        XCTAssertEqual(canonical("ws://127.0.0.1:80", configuration: .developer), "ws://127.0.0.1")
        XCTAssertEqual(
            canonical("ws://127.0.0.1:8080", configuration: .developer),
            "ws://127.0.0.1:8080"
        )
        XCTAssertEqual(relay("wss://relay.example.com:443"), relay("wss://relay.example.com"))
    }

    func testRootPathSemantics() {
        // "/" is the same relay as no path at all.
        XCTAssertEqual(canonical("wss://relay.example.com/"), "wss://relay.example.com")
        XCTAssertEqual(relay("wss://relay.example.com/"), relay("wss://relay.example.com"))
        // Deeper paths are preserved untouched, including repeated slashes.
        XCTAssertEqual(canonical("wss://relay.example.com//a"), "wss://relay.example.com//a")
        XCTAssertNotEqual(relay("wss://relay.example.com//a"), relay("wss://relay.example.com/a"))
    }

    func testPathAndQueryArePreservedExactly() {
        XCTAssertEqual(
            canonical("wss://relay.example.com/A/b/C"),
            "wss://relay.example.com/A/b/C"
        )
        XCTAssertEqual(
            canonical("wss://relay.example.com/v1?Relay=AbC&x=1"),
            "wss://relay.example.com/v1?Relay=AbC&x=1"
        )
        // Query parameter order is part of the address.
        XCTAssertNotEqual(
            relay("wss://relay.example.com/?a=1&b=2"),
            relay("wss://relay.example.com/?b=2&a=1")
        )
        // Path case is part of the address.
        XCTAssertNotEqual(
            relay("wss://relay.example.com/Path"),
            relay("wss://relay.example.com/path")
        )
    }

    func testBareQueryMarkIsPreservedAndDistinct() {
        XCTAssertEqual(canonical("wss://relay.example.com?"), "wss://relay.example.com?")
        XCTAssertNotEqual(
            relay("wss://relay.example.com?"),
            relay("wss://relay.example.com")
        )
        // A root path collapses, so this is the same relay as a bare query.
        XCTAssertEqual(
            canonical("wss://relay.example.com/path?"),
            "wss://relay.example.com/path?"
        )
    }

    func testPercentEscapeCaseIsPreservedAndDistinct() {
        XCTAssertEqual(
            canonical("wss://relay.example.com/a%2Fb"),
            "wss://relay.example.com/a%2Fb"
        )
        XCTAssertEqual(
            canonical("wss://relay.example.com/a%2fb"),
            "wss://relay.example.com/a%2fb"
        )
        // Escape case survives normalization, so these stay different relays.
        XCTAssertNotEqual(
            relay("wss://relay.example.com/a%2Fb"),
            relay("wss://relay.example.com/a%2fb")
        )
        // "/" as the path collapses to the root, leaving just the query.
        XCTAssertEqual(
            canonical("wss://relay.example.com/?q=a%20b%7Ec"),
            "wss://relay.example.com?q=a%20b%7Ec"
        )
        XCTAssertEqual(
            canonical("wss://relay.example.com/p?a%2Fb"),
            "wss://relay.example.com/p?a%2Fb"
        )
    }

    func testRejectsEmptyAndWhitespaceInput() {
        XCTAssertEqual(relayError(""), .empty)
        XCTAssertEqual(relayError("   "), .empty)
        XCTAssertEqual(relayError("\t"), .empty)
    }

    func testRejectsMissingAndUnsupportedSchemes() {
        XCTAssertEqual(relayError("relay.example.com"), .missingScheme)
        XCTAssertEqual(relayError("://relay.example.com"), .missingScheme)
        XCTAssertEqual(relayError("https://relay.example.com"), .unsupportedScheme("https"))
        XCTAssertEqual(relayError("HTTP://relay.example.com"), .unsupportedScheme("http"))
    }

    func testRejectsUserinfo() {
        XCTAssertEqual(relayError("wss://user:secret@relay.example.com"), .userinfoNotAllowed)
        XCTAssertEqual(relayError("wss://user@relay.example.com"), .userinfoNotAllowed)
    }

    func testRejectsFragments() {
        XCTAssertEqual(relayError("wss://relay.example.com/path#frag"), .fragmentNotAllowed)
        XCTAssertEqual(relayError("wss://relay.example.com#frag"), .fragmentNotAllowed)
    }

    func testRejectsControlAndEncodingRequiredCharacters() {
        XCTAssertEqual(relayError("wss://relay.example.com/\n"), .invalidCharacter(byteOffset: 24))
        XCTAssertEqual(relayError("wss://relay.example.com/a b"), .invalidCharacter(byteOffset: 25))
        XCTAssertEqual(relayError("wss://relay.example.com/\"q\""), .invalidCharacter(byteOffset: 24))
        XCTAssertEqual(relayError("wss://relay.example.com/<x>"), .invalidCharacter(byteOffset: 24))
        XCTAssertEqual(relayError("wss://relay.example.com/a|b"), .invalidCharacter(byteOffset: 25))
        // Raw non-ASCII must be percent-encoded, so it is rejected rather than guessed.
        XCTAssertEqual(relayError("wss://relay.example.com/\u{E9}"), .invalidCharacter(byteOffset: 24))
        XCTAssertEqual(relayError("wss://rel\u{E9}.com"), .invalidCharacter(byteOffset: 9))
    }

    func testRejectsInvalidPercentEscapesAtAbsoluteOffsets() {
        XCTAssertEqual(
            relayError("wss://relay.example.com/a%2"),
            .invalidPercentEscape(byteOffset: 25)
        )
        XCTAssertEqual(
            relayError("wss://relay.example.com/a%zz"),
            .invalidPercentEscape(byteOffset: 25)
        )
        XCTAssertEqual(
            relayError("wss://relay.example.com/?q=%"),
            .invalidPercentEscape(byteOffset: 27)
        )
    }

    func testRejectsBadHosts() {
        XCTAssertEqual(relayError("wss://"), .missingHost)
        XCTAssertEqual(relayError("wss:///path"), .missingHost)
        XCTAssertEqual(relayError("wss://:8080"), .missingHost)
        XCTAssertEqual(relayError("wss://.example.com"), .invalidHost(".example.com"))
        XCTAssertEqual(relayError("wss://example..com"), .invalidHost("example..com"))
        XCTAssertEqual(relayError("wss://example.com."), .invalidHost("example.com."))
        XCTAssertEqual(relayError("wss://relay%2Eexample.com"), .invalidHost("relay%2eexample.com"))
        // An unbracketed IPv6 literal is not a valid authority.
        XCTAssertEqual(relayError("wss://::1"), .invalidHost("::1"))
    }

    func testRejectsBadPorts() {
        XCTAssertEqual(relayError("wss://relay.example.com:"), .invalidPort(""))
        XCTAssertEqual(relayError("wss://relay.example.com:abc"), .invalidPort("abc"))
        XCTAssertEqual(relayError("wss://relay.example.com:-1"), .invalidPort("-1"))
        XCTAssertEqual(relayError("wss://relay.example.com:+80"), .invalidPort("+80"))
        XCTAssertEqual(relayError("wss://relay.example.com:0"), .portOutOfRange("0"))
        XCTAssertEqual(relayError("wss://relay.example.com:65536"), .portOutOfRange("65536"))
        XCTAssertEqual(
            relayError("wss://relay.example.com:99999999999"),
            .portOutOfRange("99999999999")
        )
    }

    func testRejectsInsecureRemoteWebSocket() {
        XCTAssertEqual(
            relayError("ws://relay.example.com"),
            .insecureRemoteWebSocket("relay.example.com")
        )
        XCTAssertEqual(
            relayError("ws://relay.example.com", configuration: .developer),
            .insecureRemoteWebSocket("relay.example.com")
        )
        XCTAssertEqual(
            relayError("ws://10.0.0.5:8080", configuration: .developer),
            .insecureRemoteWebSocket("10.0.0.5")
        )
    }

    func testLoopbackWebSocketRequiresDeveloperConfiguration() {
        XCTAssertEqual(relayError("ws://localhost"), .insecureLoopbackNotPermitted("localhost"))
        XCTAssertEqual(
            relayError("ws://127.0.0.1:7777"),
            .insecureLoopbackNotPermitted("127.0.0.1")
        )
        XCTAssertEqual(
            canonical("ws://localhost:7777", configuration: .developer),
            "ws://localhost:7777"
        )
        XCTAssertEqual(
            canonical("ws://127.0.0.1", configuration: .developer),
            "ws://127.0.0.1"
        )
        // Whole 127.0.0.0/8 is loopback.
        XCTAssertEqual(
            canonical("ws://127.9.9.9", configuration: .developer),
            "ws://127.9.9.9"
        )
        // wss is always acceptable, loopback or not.
        XCTAssertEqual(canonical("wss://localhost:8443"), "wss://localhost:8443")
    }

    func testNonLoopbackLookalikesAreRejected() {
        // 128.0.0.1 is not loopback even though it resembles the loopback block.
        XCTAssertEqual(
            relayError("ws://128.0.0.1", configuration: .developer),
            .insecureRemoteWebSocket("128.0.0.1")
        )
        // A hostname that merely contains "localhost" is not loopback.
        XCTAssertEqual(
            relayError("ws://localhost.example.com", configuration: .developer),
            .insecureRemoteWebSocket("localhost.example.com")
        )
    }

    func testIPv6HostsAreBracketedAndClassified() throws {
        let ipv6 = try XCTUnwrap(relay("wss://[2001:DB8::1]:8443/path"))
        XCTAssertEqual(ipv6.host, "[2001:db8::1]")
        XCTAssertEqual(ipv6.bareHost, "2001:db8::1")
        XCTAssertEqual(ipv6.port, 8443)
        XCTAssertFalse(ipv6.isLoopback)
        XCTAssertEqual(ipv6.description, "wss://[2001:db8::1]:8443/path")

        let loopback6 = try XCTUnwrap(relay("ws://[::1]:7777", configuration: .developer))
        XCTAssertTrue(loopback6.isLoopback)
        XCTAssertEqual(loopback6.description, "ws://[::1]:7777")

        XCTAssertEqual(
            relayError("ws://[::1]", configuration: .production),
            .insecureLoopbackNotPermitted("[::1]")
        )
        XCTAssertEqual(relayError("wss://[2001:db8::1"), .invalidHost("[2001:db8::1"))
        XCTAssertEqual(relayError("wss://[127.0.0.1]"), .invalidHost("[127.0.0.1]"))
    }

    func testEquivalentFormsCollapseToOneIdentity() {
        let forms = [
            "wss://Relay.Example.com",
            "WSS://relay.example.com",
            "wss://relay.example.com:443",
            "wss://RELAY.example.COM:443/",
            "wss://relay.example.com/",
        ]
        let identities = Set(forms.compactMap { relay($0) })
        XCTAssertEqual(identities.count, 1, "equivalent spellings must share one relay identity")
        XCTAssertEqual(identities.first?.description, "wss://relay.example.com")
    }

    func testDistinctRelaysStayDistinct() {
        let distinct = [
            "wss://relay.example.com",
            "wss://relay.example.com:8443",
            "wss://relay.example.com/a",
            "wss://relay.example.com/A",
            "wss://relay.example.com?a=1",
            "wss://relay.example.com/a%2Fb",
            "wss://other.example.com",
        ]
        let identities = distinct.compactMap { relay($0) }
        XCTAssertEqual(Set(identities).count, distinct.count)
    }

    func testAsURLRoundTripsTheCanonicalForm() throws {
        let parsed = try RelayURL(normalizing: "wss://Relay.Example.com:8443/Path?a=1")
        let url = try parsed.asURL()
        XCTAssertEqual(url.absoluteString, "wss://relay.example.com:8443/Path?a=1")
    }

    func testErrorDescriptionsAreUserSafe() {
        XCTAssertNotNil(RelayURLError.insecureRemoteWebSocket("r.example").errorDescription)
        XCTAssertTrue(
            RelayURLError.invalidPercentEscape(byteOffset: 4).errorDescription!.contains("4")
        )
    }
}

// MARK: - NIP-44 length arithmetic

/// Expectations here come from the pinned specification
/// (`nostr-protocol/nips@a2494f4f...`, 44.md), including its summary block:
///
///     # metadata: always 65b (version: 1b, nonce: 32b, mac: 32b)
///     # padded plaintext (small, <65536): 32b to 0x10000, with 2b prefix
///     # raw payload (small): 99 (65+34) to 65603 (65+0x10000+2)
///     # raw payload (large): 65607 (65+0x10006) to 4294967367 (65+0x100000000+6)
final class NIP44LengthTests: XCTestCase {

    func testPublishedPaddingBoundaries() throws {
        let vectors: [(plaintext: UInt64, padded: UInt64)] = [
            (1, 32), (32, 32), (33, 64), (64, 64), (65, 96), (96, 96), (97, 128),
            (128, 128), (129, 160), (160, 160), (161, 192), (256, 256), (257, 320),
            (512, 512), (1024, 1024), (4096, 4096), (8192, 8192), (16384, 16384),
            (32768, 32768), (65535, 65536), (65536, 65536), (65537, 81920),
        ]
        for vector in vectors {
            XCTAssertEqual(
                try NIP44Lengths.paddedLength(of: vector.plaintext),
                vector.padded,
                "padding for \(vector.plaintext)"
            )
        }
    }

    func testMetadataIsVersionNonceMac() throws {
        XCTAssertEqual(NIP44Lengths.metadataByteCount, 65)
        let result = try NIP44Lengths.framing(plaintextByteCount: 32)
        XCTAssertEqual(result.paddedPlaintextByteCount, 32)
        XCTAssertEqual(result.lengthPrefixByteCount, 2)
        XCTAssertFalse(result.usesExtendedPrefix)
        XCTAssertEqual(result.ciphertextByteCount, 34)
        XCTAssertEqual(result.payloadByteCount, 99)
        XCTAssertEqual(result.base64CharacterCount, 132)
    }

    // MARK: Prefix selection uses the ORIGINAL plaintext length

    func testPrefixSelectionUsesPlaintextLengthNotPaddedLength() throws {
        // 65535 pads to 65536, yet the prefix still encodes the *plaintext*
        // length, so it stays in the 2-byte form.
        let below = try NIP44Lengths.framing(plaintextByteCount: 65535)
        XCTAssertEqual(below.paddedPlaintextByteCount, 65536)
        XCTAssertEqual(below.lengthPrefixByteCount, 2)
        XCTAssertFalse(below.usesExtendedPrefix)
        XCTAssertEqual(below.ciphertextByteCount, 65538)
        XCTAssertEqual(below.payloadByteCount, 65603)
        XCTAssertEqual(below.base64CharacterCount, 87472)

        // 65536 reaches the threshold and switches to the 6-byte prefix, even
        // though its padded length is unchanged at 65536.
        let at = try NIP44Lengths.framing(plaintextByteCount: 65536)
        XCTAssertEqual(at.paddedPlaintextByteCount, 65536)
        XCTAssertEqual(at.lengthPrefixByteCount, 6)
        XCTAssertTrue(at.usesExtendedPrefix)
        XCTAssertEqual(at.ciphertextByteCount, 65542)
        XCTAssertEqual(at.payloadByteCount, 65607)
        XCTAssertEqual(at.base64CharacterCount, 87476)

        // The threshold is a property of the plaintext length only.
        XCTAssertEqual(try NIP44Lengths.lengthPrefixByteCount(forPlaintextLength: 65535), 2)
        XCTAssertEqual(try NIP44Lengths.lengthPrefixByteCount(forPlaintextLength: 65536), 6)
        XCTAssertEqual(try NIP44Lengths.lengthPrefixByteCount(forPlaintextLength: 65534), 2)
    }

    func testContractBoundaryArithmeticFor65537() throws {
        // 65,537 plaintext bytes pad to 81,920; with the 6-byte prefix and the
        // 65-byte metadata the raw payload is 81,991 bytes, which is 109,324
        // padded Base64 characters.
        let result = try NIP44Lengths.framing(plaintextByteCount: 65537)
        XCTAssertEqual(result.paddedPlaintextByteCount, 81920)
        XCTAssertEqual(result.lengthPrefixByteCount, 6)
        XCTAssertEqual(result.ciphertextByteCount, 81926)
        XCTAssertEqual(result.payloadByteCount, 81991)
        XCTAssertEqual(result.base64CharacterCount, 109324)
    }

    func testSpecPayloadRangeEndpoints() throws {
        let unbounded = NIP44Limits(
            applicationPlaintextCap: UInt64.max,
            outerWireCap: UInt64.max
        )
        // Smallest raw payload: 99 bytes for a 1-byte plaintext.
        XCTAssertEqual(
            try NIP44Lengths.framing(plaintextByteCount: 1, limits: unbounded).payloadByteCount,
            99
        )
        // Largest raw payload: 4,294,967,367 for a 2^32-1 plaintext.
        XCTAssertEqual(
            try NIP44Lengths.framing(
                plaintextByteCount: NIP44Lengths.theoreticalMaximumPlaintextByteCount,
                limits: unbounded
            ).payloadByteCount,
            4_294_967_367
        )
    }

    // MARK: Limits

    func testEmptyAndAboveTheoreticalMaximumAreRejected() {
        XCTAssertEqual(framingError(0), .emptyPlaintext)
        let above = NIP44Lengths.theoreticalMaximumPlaintextByteCount + 1
        XCTAssertEqual(framingError(above), .plaintextAboveTheoreticalMaximum(above))
    }

    func testTheoreticalMaximumPlaintextIsAcceptedAndPadsToTwoPow32() throws {
        // `calc_padded_len` may exceed 2^32-1; only the *plaintext* length is
        // capped, so this is valid framing rather than an error.
        let unbounded = NIP44Limits(
            applicationPlaintextCap: UInt64.max,
            outerWireCap: UInt64.max
        )
        let maximum = NIP44Lengths.theoreticalMaximumPlaintextByteCount
        let result = try NIP44Lengths.framing(plaintextByteCount: maximum, limits: unbounded)
        XCTAssertEqual(result.paddedPlaintextByteCount, 1 << 32)
        XCTAssertEqual(result.lengthPrefixByteCount, 6)
        XCTAssertEqual(result.ciphertextByteCount, (1 << 32) + 6)
        XCTAssertEqual(result.payloadByteCount, 4_294_967_367)
    }

    func testApplicationPlaintextCapIsSeparateFromWireCap() {
        // Exactly 1 MiB is accepted by the default app cap.
        let atCap = framing(NIP44Limits.defaultPlaintextCap)
        XCTAssertNotNil(atCap)
        XCTAssertEqual(atCap?.paddedPlaintextByteCount, NIP44Limits.defaultPlaintextCap)

        // One byte more fails against the plaintext cap.
        XCTAssertEqual(
            framingError(NIP44Limits.defaultPlaintextCap + 1),
            .plaintextAboveApplicationCap(
                bytes: NIP44Limits.defaultPlaintextCap + 1,
                cap: NIP44Limits.defaultPlaintextCap
            )
        )

        // A tiny wire cap fails on encoded length even for a small plaintext,
        // proving the two limits are enforced independently.
        let tinyWire = NIP44Limits(applicationPlaintextCap: 1 << 20, outerWireCap: 100)
        XCTAssertEqual(
            framingError(32, limits: tinyWire),
            .payloadAboveWireCap(encodedCharacters: 132, cap: 100)
        )
        XCTAssertNil(framing(64, limits: tinyWire))
    }

    func testCapsAreDistinctConstants() {
        XCTAssertEqual(NIP44Limits.defaultPlaintextCap, 1_048_576)
        XCTAssertEqual(NIP44Limits.defaultWireCap, 2_097_152)
        XCTAssertEqual(NIP44Lengths.theoreticalMaximumPlaintextByteCount, 4_294_967_295)
        XCTAssertEqual(NIP44Lengths.extendedPrefixThreshold, 65_536)
        XCTAssertEqual(NIP44Limits.standard.applicationPlaintextCap, NIP44Limits.defaultPlaintextCap)
        XCTAssertEqual(NIP44Limits.standard.outerWireCap, NIP44Limits.defaultWireCap)
    }

    func testLargerPlaintextStaysUnderTheWireCap() throws {
        let result = try NIP44Lengths.framing(plaintextByteCount: NIP44Limits.defaultPlaintextCap)
        XCTAssertLessThan(result.base64CharacterCount, NIP44Limits.defaultWireCap)
        XCTAssertEqual(result.base64CharacterCount, 1_398_196)
    }

    // MARK: Length prefix codec

    func testLengthPrefixEncodingBoundaries() throws {
        XCTAssertEqual(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 1), [0x00, 0x01])
        XCTAssertEqual(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 32), [0x00, 0x20])
        XCTAssertEqual(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 255), [0x00, 0xFF])
        XCTAssertEqual(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 256), [0x01, 0x00])
        XCTAssertEqual(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 65535), [0xFF, 0xFF])
        // Threshold is on the plaintext length: 65536 uses the extended form.
        XCTAssertEqual(
            try NIP44Lengths.encodeLengthPrefix(plaintextLength: 65536),
            [0x00, 0x00, 0x00, 0x01, 0x00, 0x00]
        )
        XCTAssertEqual(
            try NIP44Lengths.encodeLengthPrefix(plaintextLength: 81920),
            [0x00, 0x00, 0x00, 0x01, 0x40, 0x00]
        )
        // The extended form is never emitted for a shorter message.
        XCTAssertEqual(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 65534).count, 2)
        XCTAssertEqual(
            try NIP44Lengths.encodeLengthPrefix(
                plaintextLength: NIP44Lengths.theoreticalMaximumPlaintextByteCount
            ),
            [0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]
        )
        XCTAssertThrowsError(try NIP44Lengths.encodeLengthPrefix(plaintextLength: 0)) { error in
            XCTAssertEqual(error as? NIP44LengthError, .emptyPlaintext)
        }
    }

    func testLengthPrefixRoundTripsPlaintextLength() throws {
        let lengths: [UInt64] = [
            1, 32, 33, 255, 256, 65_535, 65_536, 65_537, 81_920,
            NIP44Lengths.theoreticalMaximumPlaintextByteCount,
        ]
        for length in lengths {
            let encoded = try NIP44Lengths.encodeLengthPrefix(plaintextLength: length)
            let decoded = try NIP44Lengths.decodeLengthPrefix(encoded[...])
            XCTAssertEqual(decoded.plaintextLength, length, "round trip for \(length)")
            XCTAssertEqual(decoded.prefixByteCount, encoded.count)
        }
    }

    func testLengthPrefixDecodingIgnoresTrailingPayloadBytes() throws {
        let short: [UInt8] = [0x00, 0x20] + [UInt8](repeating: 0xAA, count: 50)
        let shortDecoded = try NIP44Lengths.decodeLengthPrefix(short[...])
        XCTAssertEqual(shortDecoded.prefixByteCount, 2)
        XCTAssertEqual(shortDecoded.plaintextLength, 32)

        let extended: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x40, 0x00]
            + [UInt8](repeating: 0xBB, count: 50)
        let extendedDecoded = try NIP44Lengths.decodeLengthPrefix(extended[...])
        XCTAssertEqual(extendedDecoded.prefixByteCount, 6)
        XCTAssertEqual(extendedDecoded.plaintextLength, 81_920)
    }

    func testExtendedPrefixBelowThresholdIsRejected() {
        func decode(_ bytes: [UInt8]) -> NIP44LengthError? {
            do {
                _ = try NIP44Lengths.decodeLengthPrefix(bytes[...])
                return nil
            } catch let error as NIP44LengthError {
                return error
            } catch {
                return nil
            }
        }
        // The spec's `unpad` rejects an extended prefix encoding < 65536.
        XCTAssertEqual(
            decode([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            .nonCanonicalExtendedPrefix(0)
        )
        XCTAssertEqual(
            decode([0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF]),
            .nonCanonicalExtendedPrefix(65_535)
        )
        // 65536 is the first canonical extended value.
        XCTAssertNil(decode([0x00, 0x00, 0x00, 0x01, 0x00, 0x00]))
    }

    func testLengthPrefixDecodingRejectsMalformedInput() {
        func decode(_ bytes: [UInt8]) -> NIP44LengthError? {
            do {
                _ = try NIP44Lengths.decodeLengthPrefix(bytes[...])
                return nil
            } catch let error as NIP44LengthError {
                return error
            } catch {
                return nil
            }
        }
        XCTAssertEqual(decode([]), .malformedLengthPrefix)
        XCTAssertEqual(decode([0x00]), .malformedLengthPrefix)
        XCTAssertEqual(decode([0x00, 0x00]), .malformedLengthPrefix)
        XCTAssertEqual(decode([0x00, 0x00, 0x00, 0x01]), .malformedLengthPrefix)
        XCTAssertNil(decode([0x00, 0x01]))
        XCTAssertNil(decode([0xFF, 0xFF]))
    }

    // MARK: Base64 length

    func testBase64CharacterCounts() throws {
        let counts: [(bytes: UInt64, characters: UInt64)] = [
            (0, 0), (1, 4), (2, 4), (3, 4), (4, 8), (5, 8), (6, 8), (7, 12),
            (99, 132), (131, 176), (81_991, 109_324), (65_603, 87_472), (65_607, 87_476),
        ]
        for item in counts {
            XCTAssertEqual(
                try NIP44Lengths.base64CharacterCount(forByteCount: item.bytes),
                item.characters,
                "base64 length for \(item.bytes) bytes"
            )
        }
    }

    func testBase64CharacterCountReportsOverflowInsteadOfTrapping() {
        XCTAssertThrowsError(
            try NIP44Lengths.base64CharacterCount(forByteCount: UInt64.max)
        ) { error in
            XCTAssertEqual(
                error as? NIP44LengthError,
                .lengthArithmeticOverflow(UInt64.max)
            )
        }
        XCTAssertThrowsError(
            try NIP44Lengths.base64CharacterCount(forByteCount: UInt64.max - 1)
        ) { error in
            XCTAssertEqual(
                error as? NIP44LengthError,
                .lengthArithmeticOverflow(UInt64.max - 1)
            )
        }
        // A value whose group count but not adjusted byte count overflows.
        XCTAssertThrowsError(
            try NIP44Lengths.base64CharacterCount(forByteCount: UInt64.max - 3)
        )
    }

    func testErrorDescriptionsAreUserSafe() {
        XCTAssertNotNil(NIP44LengthError.emptyPlaintext.errorDescription)
        XCTAssertTrue(
            NIP44LengthError.plaintextAboveApplicationCap(bytes: 9, cap: 5)
                .errorDescription!.contains("9")
        )
        XCTAssertTrue(
            NIP44LengthError.nonCanonicalExtendedPrefix(65_535)
                .errorDescription!.contains("65535")
        )
    }
}

// MARK: - Replaceable event ordering

final class ReplaceableOrderingTests: XCTestCase {

    private func articleAddress(_ pubkey: [UInt8] = pubkeyA, d: String = "abc") throws
        -> ReplaceableAddress {
        try ReplaceableAddress(kind: 30023, pubkey: pubkey, dTag: d)
    }

    private func event(
        _ address: ReplaceableAddress,
        createdAt: Int64,
        id idByte: UInt8,
        expiration: Int64? = nil
    ) throws -> VerifiedReplaceableEvent {
        VerifiedReplaceableEvent(
            address: address,
            createdAt: createdAt,
            eventID: try id(idByte),
            expiration: expiration
        )
    }

    func testHighestCreatedAtWins() throws {
        let address = try articleAddress()
        let older = try event(address, createdAt: 100, id: 0xFF)
        let newer = try event(address, createdAt: 101, id: 0x00)
        XCTAssertTrue(try ReplaceableOrdering.supersedes(newer, older))
        XCTAssertFalse(try ReplaceableOrdering.supersedes(older, newer))
        XCTAssertEqual(ReplaceableOrdering.winner(of: [older, newer])?.eventID.bytes[0], 0x00)
        XCTAssertEqual(ReplaceableOrdering.winner(of: [newer, older])?.eventID.bytes[0], 0x00)
    }

    func testEqualTimestampsUseLowestEventID() throws {
        let address = try articleAddress()
        let lowID = try event(address, createdAt: 500, id: 0x01)
        let highID = try event(address, createdAt: 500, id: 0xFE)
        XCTAssertTrue(try ReplaceableOrdering.supersedes(lowID, highID))
        XCTAssertFalse(try ReplaceableOrdering.supersedes(highID, lowID))
        XCTAssertEqual(ReplaceableOrdering.winner(of: [highID, lowID])?.eventID.bytes[0], 0x01)
        XCTAssertEqual(ReplaceableOrdering.winner(of: [lowID, highID])?.eventID.bytes[0], 0x01)
    }

    func testTimestampDominatesEventIDTieBreak() throws {
        let address = try articleAddress()
        let older = try event(address, createdAt: 10, id: 0x00)
        let newer = try event(address, createdAt: 11, id: 0xFF)
        XCTAssertTrue(try ReplaceableOrdering.supersedes(newer, older))
        XCTAssertEqual(ReplaceableOrdering.winner(of: [older, newer])?.createdAt, 11)
    }

    func testIdenticalEventIDNeverReplaces() throws {
        let address = try articleAddress()
        let first = try event(address, createdAt: 700, id: 0x42)
        let second = try event(address, createdAt: 700, id: 0x42)
        XCTAssertFalse(try ReplaceableOrdering.supersedes(first, second))
        XCTAssertFalse(try ReplaceableOrdering.supersedes(second, first))
        XCTAssertEqual(ReplaceableOrdering.winner(of: [first, second]), first)
    }

    func testSupersedesThrowsOnAddressMismatch() throws {
        let article = try articleAddress()
        let otherDTag = try articleAddress(d: "different")
        let otherAuthor = try articleAddress(pubkeyB)
        let base = try event(article, createdAt: 1, id: 0x01)

        XCTAssertThrowsError(
            try ReplaceableOrdering.supersedes(try event(otherDTag, createdAt: 9, id: 0x02), base)
        ) { error in
            XCTAssertEqual(error as? ReplaceableOrderingError, .addressMismatch)
        }
        XCTAssertThrowsError(
            try ReplaceableOrdering.supersedes(try event(otherAuthor, createdAt: 9, id: 0x03), base)
        ) { error in
            XCTAssertEqual(error as? ReplaceableOrderingError, .addressMismatch)
        }
    }

    func testWinnerIgnoresEventsFromOtherAddresses() throws {
        let article = try articleAddress()
        let otherAuthor = try articleAddress(pubkeyB)
        let mine = try event(article, createdAt: 1, id: 0x01)
        let foreign = try event(otherAuthor, createdAt: 9_999, id: 0x02)
        // The first event anchors the comparison, so the unrelated one cannot win.
        XCTAssertEqual(ReplaceableOrdering.winner(of: [mine, foreign]), mine)
        XCTAssertEqual(ReplaceableOrdering.winner(of: [foreign, mine]), foreign)
        XCTAssertNil(ReplaceableOrdering.winner(of: []))
    }

    func testExpiredEventsAreSkipped() throws {
        let address = try articleAddress()
        let earlyExpiry = try event(address, createdAt: 9_000, id: 0x01, expiration: 1_500)
        let lateExpiry = try event(address, createdAt: 100, id: 0x02, expiration: 5_000)
        let noExpiration = try event(address, createdAt: 50, id: 0x03)

        // Without a clock, the newest wins regardless of expiration.
        XCTAssertEqual(ReplaceableOrdering.winner(of: [earlyExpiry, lateExpiry])?.createdAt, 9_000)
        // With a clock, the expired event is dropped even though it is newest.
        XCTAssertEqual(
            ReplaceableOrdering.winner(of: [earlyExpiry, lateExpiry], at: 2_000)?.createdAt,
            100
        )
        // Expiration is inclusive, so at exactly its timestamp an event is gone.
        XCTAssertNil(ReplaceableOrdering.winner(of: [earlyExpiry, lateExpiry], at: 5_000))
        XCTAssertEqual(
            ReplaceableOrdering.winner(of: [earlyExpiry, lateExpiry], at: 4_999)?.createdAt,
            100
        )
        // An event without an expiration never expires.
        XCTAssertFalse(noExpiration.isExpired(at: Int64.max))
        XCTAssertNil(ReplaceableOrdering.winner(of: [earlyExpiry], at: 10_000))
        XCTAssertEqual(
            ReplaceableOrdering.winner(of: [noExpiration], at: Int64.max)?.createdAt,
            50
        )
    }

    func testResolveGroupsByAddress() throws {
        let firstArticle = try ReplaceableAddress(kind: 30023, pubkey: pubkeyA, dTag: "one")
        let secondArticle = try ReplaceableAddress(kind: 30023, pubkey: pubkeyA, dTag: "two")
        let profile = try ReplaceableAddress(kind: 0, pubkey: pubkeyB)
        let draft = try ReplaceableAddress(kind: 31234, pubkey: pubkeyB, dTag: "draft-1")

        let events = [
            try event(firstArticle, createdAt: 10, id: 0x0A),
            try event(firstArticle, createdAt: 20, id: 0x0B),
            try event(secondArticle, createdAt: 30, id: 0x0C),
            try event(profile, createdAt: 40, id: 0x0D),
            try event(profile, createdAt: 35, id: 0x0E),
            try event(draft, createdAt: 50, id: 0x0F, expiration: 60),
        ]

        // The only draft version is expired at t=100, so that address drops out.
        let winners = ReplaceableOrdering.resolve(events, at: 100)
        XCTAssertEqual(winners.count, 3)
        XCTAssertEqual(winners[firstArticle]?.createdAt, 20)
        XCTAssertEqual(winners[secondArticle]?.createdAt, 30)
        XCTAssertEqual(winners[profile]?.createdAt, 40)
        XCTAssertNil(winners[draft])

        let withoutClock = ReplaceableOrdering.resolve(events)
        XCTAssertEqual(withoutClock.count, 4)
        XCTAssertEqual(withoutClock[draft]?.createdAt, 50)
    }

    func testEventIDValidation() throws {
        let zeros = try EventID(hex: String(repeating: "0", count: 64))
        XCTAssertEqual(zeros.bytes, [UInt8](repeating: 0, count: 32))
        XCTAssertEqual(zeros.hex, String(repeating: "0", count: 64))

        let ones = try EventID(bytes: [UInt8](repeating: 0xFF, count: 32))
        XCTAssertEqual(ones.hex, String(repeating: "f", count: 64))

        // Uppercase hexadecimal is accepted and normalizes to the same bytes.
        let upper = try EventID(hex: "AB" + String(repeating: "0", count: 62))
        let lower = try EventID(hex: "ab" + String(repeating: "0", count: 62))
        XCTAssertEqual(upper, lower)
        XCTAssertEqual(upper.bytes[0], 0xAB)
        XCTAssertTrue(upper.hex.hasPrefix("ab"))

        XCTAssertThrowsError(try EventID(bytes: [UInt8](repeating: 0, count: 31))) { error in
            XCTAssertEqual(error as? ReplaceableOrderingError, .invalidEventIDLength(31))
        }
        XCTAssertThrowsError(try EventID(bytes: [UInt8](repeating: 0, count: 33))) { error in
            XCTAssertEqual(error as? ReplaceableOrderingError, .invalidEventIDLength(33))
        }
        XCTAssertThrowsError(try EventID(hex: String(repeating: "0", count: 63))) { error in
            XCTAssertEqual(error as? ReplaceableOrderingError, .invalidEventIDLength(63))
        }
        XCTAssertThrowsError(try EventID(hex: String(repeating: "g", count: 64))) { error in
            XCTAssertEqual(
                error as? ReplaceableOrderingError,
                .invalidEventIDText(String(repeating: "g", count: 64))
            )
        }
    }

    func testByteOrderMatchesLexicalHexOrder() throws {
        // Unsigned byte comparison and lowercase hex comparison must agree,
        // which is what makes "lowest id" unambiguous.
        let pairs: [(UInt8, UInt8)] = [(0x00, 0x01), (0x0F, 0x10), (0x7F, 0x80), (0xFE, 0xFF)]
        for pair in pairs {
            let low = try id(pair.0)
            let high = try id(pair.1)
            XCTAssertTrue(low.bytes.lexicographicallyPrecedes(high.bytes))
            XCTAssertLessThan(low.hex, high.hex)
        }
    }

    func testReplaceableKindClassification() {
        XCTAssertEqual(ReplaceableAddress.classification(of: 0).replaceable, true)
        XCTAssertEqual(ReplaceableAddress.classification(of: 0).addressable, false)
        XCTAssertEqual(ReplaceableAddress.classification(of: 3).replaceable, true)
        XCTAssertEqual(ReplaceableAddress.classification(of: 10002).replaceable, true)
        XCTAssertEqual(ReplaceableAddress.classification(of: 10013).addressable, false)
        XCTAssertEqual(ReplaceableAddress.classification(of: 30023).replaceable, true)
        XCTAssertEqual(ReplaceableAddress.classification(of: 30023).addressable, true)
        XCTAssertEqual(ReplaceableAddress.classification(of: 31234).addressable, true)
        XCTAssertEqual(ReplaceableAddress.classification(of: 1).replaceable, false)
        XCTAssertEqual(ReplaceableAddress.classification(of: 22242).replaceable, false)
    }

    func testAddressRequiresDTagForAddressableKinds() throws {
        XCTAssertNil(addressError(kind: 30023, pubkey: pubkeyA, dTag: "id"))
        XCTAssertNil(addressError(kind: 30023, pubkey: pubkeyA, dTag: ""))
        XCTAssertEqual(
            addressError(kind: 30023, pubkey: pubkeyA, dTag: nil),
            .missingDTag(kind: 30023)
        )
        XCTAssertEqual(
            addressError(kind: 31234, pubkey: pubkeyA, dTag: nil),
            .missingDTag(kind: 31234)
        )
    }

    func testAddressRejectsDTagForNonAddressableKinds() throws {
        XCTAssertNil(addressError(kind: 0, pubkey: pubkeyA, dTag: nil))
        XCTAssertNil(addressError(kind: 3, pubkey: pubkeyA, dTag: nil))
        XCTAssertNil(addressError(kind: 10002, pubkey: pubkeyA, dTag: nil))
        XCTAssertEqual(
            addressError(kind: 0, pubkey: pubkeyA, dTag: "d"),
            .unexpectedDTag(kind: 0)
        )
        XCTAssertEqual(
            addressError(kind: 10002, pubkey: pubkeyA, dTag: "d"),
            .unexpectedDTag(kind: 10002)
        )
    }

    func testAddressRejectsNonReplaceableKindsAndBadPubkeys() {
        XCTAssertEqual(
            addressError(kind: 1, pubkey: pubkeyA, dTag: nil),
            .notReplaceable(kind: 1)
        )
        XCTAssertEqual(
            addressError(kind: 22242, pubkey: pubkeyA, dTag: nil),
            .notReplaceable(kind: 22242)
        )
        XCTAssertEqual(
            addressError(kind: 0, pubkey: [UInt8](repeating: 0, count: 31), dTag: nil),
            .invalidPubkeyLength(31)
        )
    }

    func testDistinctDTagsAreDistinctAddresses() throws {
        let one = try ReplaceableAddress(kind: 30023, pubkey: pubkeyA, dTag: "one")
        let two = try ReplaceableAddress(kind: 30023, pubkey: pubkeyA, dTag: "two")
        let sameAsOne = try ReplaceableAddress(kind: 30023, pubkey: pubkeyA, dTag: "one")
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(one, sameAsOne)
        XCTAssertEqual(Set([one, two, sameAsOne]).count, 2)
    }

    func testErrorDescriptionsAreUserSafe() {
        XCTAssertNotNil(ReplaceableOrderingError.addressMismatch.errorDescription)
        XCTAssertTrue(
            ReplaceableOrderingError.missingDTag(kind: 30023).errorDescription!.contains("30023")
        )
    }
}
