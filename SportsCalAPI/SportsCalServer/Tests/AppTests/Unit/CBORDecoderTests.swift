@testable import App
import XCTest

/// Exercises the hand-rolled CBOR decoder against RFC 8949 Appendix A vectors
/// plus the malformed inputs it exists to reject. This parser reads
/// unauthenticated bytes on the attestation path, so the negative cases matter
/// as much as the positive ones.
final class CBORDecoderTests: XCTestCase {

    private func decode(_ hex: String) throws -> CBOR {
        try CBORDecoder.decode(Data(hexString: hex))
    }

    // MARK: - RFC 8949 Appendix A

    func test_unsignedIntegers() throws {
        XCTAssertEqual(try decode("00").intValue, 0)
        XCTAssertEqual(try decode("17").intValue, 23)      // largest single-byte
        XCTAssertEqual(try decode("1818").intValue, 24)    // 1-byte extension
        XCTAssertEqual(try decode("1903e8").intValue, 1000)
        XCTAssertEqual(try decode("1a000f4240").intValue, 1_000_000)
        XCTAssertEqual(try decode("1b000000e8d4a51000").intValue, 1_000_000_000_000)
    }

    func test_negativeIntegers() throws {
        XCTAssertEqual(try decode("20").intValue, -1)
        XCTAssertEqual(try decode("29").intValue, -10)
        XCTAssertEqual(try decode("3903e7").intValue, -1000)
    }

    func test_byteAndTextStrings() throws {
        XCTAssertEqual(try decode("40").bytes, [])
        XCTAssertEqual(try decode("4401020304").bytes, [1, 2, 3, 4])
        XCTAssertEqual(try decode("60").text, "")
        XCTAssertEqual(try decode("6449455446").text, "IETF")
        // Multi-byte UTF-8 must survive intact.
        XCTAssertEqual(try decode("62c3bc").text, "ü")
    }

    func test_arrays() throws {
        XCTAssertEqual(try decode("80").arrayValue?.count, 0)
        XCTAssertEqual(try decode("83010203").arrayValue?.compactMap(\.intValue), [1, 2, 3])
        // Nested: [1, [2, 3], [4, 5]]
        let nested = try decode("8301820203820405")
        XCTAssertEqual(nested.arrayValue?.count, 3)
        XCTAssertEqual(nested.arrayValue?[1].arrayValue?.compactMap(\.intValue), [2, 3])
    }

    func test_textKeyedMap() throws {
        // {"a": 1, "b": [2, 3]}
        let map = try decode("a26161016162820203")
        XCTAssertEqual(map["a"]?.intValue, 1)
        XCTAssertEqual(map["b"]?.arrayValue?.compactMap(\.intValue), [2, 3])
        XCTAssertNil(map["missing"])
    }

    func test_integerKeyedMap_asUsedByCOSEKeys() throws {
        // {1: 2, -3: 4} — COSE uses both positive and negative integer labels.
        let map = try decode("a201022204")
        XCTAssertEqual(map[1]?.intValue, 2)
        XCTAssertEqual(map[-3]?.intValue, 4)
    }

    func test_simpleValues() throws {
        XCTAssertEqual(try decode("f4"), .boolean(false))
        XCTAssertEqual(try decode("f5"), .boolean(true))
        XCTAssertEqual(try decode("f6"), .null)
    }

    // MARK: - Rejections

    func test_rejectsTrailingBytes() {
        // A valid `0` followed by a stray byte. Accepting this would let a
        // caller hide a second payload behind the one we validate.
        XCTAssertThrowsError(try decode("0000")) { XCTAssertEqual($0 as? CBORError, .trailingBytes) }
    }

    func test_rejectsIndefiniteLength() {
        XCTAssertThrowsError(try decode("5f42010243030405ff")) {
            XCTAssertEqual($0 as? CBORError, .indefiniteLength)
        }
    }

    func test_rejectsTruncatedInput() {
        // Declares a 4-byte string, supplies two. Caught by the length check
        // before any allocation, so it surfaces as .lengthTooLarge rather than
        // .truncated — both are fail-closed, this pins which one.
        XCTAssertThrowsError(try decode("440102")) { XCTAssertEqual($0 as? CBORError, .lengthTooLarge) }
    }

    func test_rejectsTruncatedArgument() {
        // Announces a 4-byte integer argument but the input ends first.
        XCTAssertThrowsError(try decode("1a0102")) { XCTAssertEqual($0 as? CBORError, .truncated) }
    }

    func test_rejectsAbsurdLengthWithoutAllocating() {
        // Claims a 2^32-byte string in a 5-byte buffer — must fail on the length
        // check, not by trying to reserve 4GB.
        XCTAssertThrowsError(try decode("5affffffff")) {
            XCTAssertEqual($0 as? CBORError, .lengthTooLarge)
        }
    }

    func test_rejectsDuplicateMapKeys() {
        // {"a": 1, "a": 2} — ambiguous, and a classic way to smuggle a second
        // value past a validator that reads the first.
        XCTAssertThrowsError(try decode("a2616101616102")) {
            XCTAssertEqual($0 as? CBORError, .duplicateMapKey)
        }
    }

    func test_rejectsTags() {
        // Tag 0 wrapping a text string — App Attest never emits tags.
        XCTAssertThrowsError(try decode("c06131")) {
            XCTAssertEqual($0 as? CBORError, .unsupportedMajorType(6))
        }
    }

    func test_rejectsFloats() {
        XCTAssertThrowsError(try decode("fb3ff199999999999a"))
    }

    func test_rejectsInvalidUTF8() {
        // 0x61 = 1-byte text string, 0xff is not valid UTF-8.
        XCTAssertThrowsError(try decode("61ff")) { XCTAssertEqual($0 as? CBORError, .invalidUTF8) }
    }

    func test_rejectsDeepNesting() {
        // 20 nested single-element arrays — past the depth limit.
        let deep = String(repeating: "81", count: 20) + "00"
        XCTAssertThrowsError(try decode(deep)) {
            XCTAssertEqual($0 as? CBORError, .depthLimitExceeded)
        }
    }

    func test_rejectsNonTextNonIntegerMapKey() {
        // {[]: 1} — array key.
        XCTAssertThrowsError(try decode("a18001")) {
            XCTAssertEqual($0 as? CBORError, .unsupportedMapKey)
        }
    }

    // MARK: - Prefix decoding

    func test_decodePrefixReportsConsumedBytes() throws {
        // A map followed by unrelated trailing bytes — decodePrefix stops at the
        // end of the map rather than erroring, which is how authenticatorData's
        // trailing COSE key is located.
        let (value, consumed) = try CBORDecoder.decodePrefix(Data(hexString: "a1616101deadbeef"))
        XCTAssertEqual(value["a"]?.intValue, 1)
        XCTAssertEqual(consumed, 4)
    }
}

// MARK: - Helpers

extension Data {
    /// Test-only hex literal parser. Ignores nothing and asserts on bad input —
    /// a typo in a vector should fail loudly, not decode to something else.
    init(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            precondition(next <= hexString.endIndex, "hex string has odd length: \(hexString)")
            guard let byte = UInt8(hexString[index..<next], radix: 16) else {
                preconditionFailure("invalid hex byte in: \(hexString)")
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
