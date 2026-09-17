import XCTest
@testable import WriterHWP

final class CanonicalCBORTests: XCTestCase {
    private func hex(_ value: String) -> Data {
        let characters = Array(value.utf8)
        return Data(stride(from: 0, to: characters.count, by: 2).map { index in
            UInt8(String(decoding: characters[index..<index+2], as: UTF8.self), radix: 16)!
        })
    }

    func testFrozenVectorAndObjectPoolDecodingMatchesPythonOracle() throws {
        let rows = try FrozenOracle.cborRows()
        XCTAssertEqual(rows.count, 61)
        for row in rows {
            let bytes = hex(row.hex)
            if row.valid {
                let value = try HWPCBOR.decode(bytes)
                XCTAssertEqual(try HWPCBOR.encode(value), bytes, row.id)
            } else { XCTAssertThrowsError(try HWPCBOR.decode(bytes), row.id) }
        }
    }

    func testCoreBytewiseOrderingIsNotLengthFirst() throws {
        let value = HWPValue.map([HWPEntry(.negative(-1), .unsigned(2)), HWPEntry(.unsigned(24), .unsigned(1))])
        XCTAssertEqual(try HWPCBOR.encode(value), hex("a21818012002"))
        XCTAssertThrowsError(try HWPCBOR.decode(hex("a22002181801")))
        XCTAssertEqual(value, .map([HWPEntry(.unsigned(24), .unsigned(1)), HWPEntry(.negative(-1), .unsigned(2))]))
    }

    func testUnicodeByteIdentityAndBOMArePreserved() throws {
        XCTAssertNotEqual(HWPValue.text("é"), HWPValue.text("e\u{301}"))
        let map = HWPValue.map([HWPEntry(.text("é"), .unsigned(1)), HWPEntry(.text("e\u{301}"), .unsigned(2))])
        let encoded = try HWPCBOR.encode(map)
        guard case .map(let pairs) = try HWPCBOR.decode(encoded) else { return XCTFail("Expected map") }
        XCTAssertEqual(pairs.count, 2)
        XCTAssertNotEqual(pairs[0].key, pairs[1].key)
        let bom = HWPValue.text(Data([0xef, 0xbb, 0xbf]))
        XCTAssertEqual(try HWPCBOR.decode(HWPCBOR.encode(bom)), bom)
    }

    func testIntegersBooleansAndMapKeysHaveDistinctDomains() throws {
        for value in [HWPValue.unsigned(UInt64.max), .negative(Int64.min), .boolean(true), .boolean(false), .null] {
            XCTAssertEqual(try HWPCBOR.decode(HWPCBOR.encode(value)), value)
        }
        XCTAssertThrowsError(try HWPCBOR.encode(.negative(0)))
        XCTAssertThrowsError(try HWPCBOR.decode(hex("3b8000000000000000")))
        XCTAssertThrowsError(try HWPCBOR.encode(.map([HWPEntry(.boolean(true), .null)])))
        XCTAssertThrowsError(try HWPCBOR.decode(hex("a1f500")))
        XCTAssertThrowsError(try HWPCBOR.encode(.map([HWPEntry(.text("x"), .null), HWPEntry(.text("x"), .null)])))
    }

    func testMalformedUTF8NonminimalAndImpossibleLengthsReject() {
        for bad in ["62c0af", "63eda080", "64f4908080", "18", "1bffffffff", "5bffffffffffffffff", "9bffffffffffffffff", "bbffffffffffffffff", "f7", "faffffffff", "d818f6"] {
            XCTAssertThrowsError(try HWPCBOR.decode(hex(bad)), bad)
        }
        XCTAssertThrowsError(try HWPCBOR.encode(.text(Data([0xff]))))
        XCTAssertNoThrow(try HWPCBOR.decode(hex("d2f6"))) // Syntax only; COSE checks the contents later.
    }

    func testDepthAndGlobalItemBudgetRejectBeforeUnboundedWork() throws {
        var nested = HWPValue.null
        for _ in 0..<32 { nested = .array([nested]) }
        XCTAssertNoThrow(try HWPCBOR.decode(HWPCBOR.encode(nested)))
        XCTAssertThrowsError(try HWPCBOR.encode(.array([nested])))
        let tooDeep = Data(repeating: 0x81, count: 33) + Data([0xf6])
        XCTAssertThrowsError(try HWPCBOR.decode(tooDeep))
        let tooMany = hex("9a000186a0") + Data(repeating: 0, count: 100_000)
        XCTAssertThrowsError(try HWPCBOR.decode(tooMany))
    }

    func testSlicedInputAndTruncationNeverTrap() throws {
        let source = Data([0x00, 0x62, 0xc3, 0xa9]).dropFirst()
        XCTAssertEqual(try HWPCBOR.decode(source), .text("é"))
        let complete = try HWPCBOR.encode(.map([HWPEntry(.text("nested"), .array([.unsigned(1000), .tag18(.null)]))]))
        for end in 0..<complete.count { XCTAssertThrowsError(try HWPCBOR.decode(complete.prefix(end))) }
    }
}
