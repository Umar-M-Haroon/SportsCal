@testable import App
import Foundation
import XCTest

/// Tests for the App Attest receipt parser.
///
/// Apple publishes no sample receipts and one can only be obtained by calling
/// their server with a real device's attestation, so these build synthetic
/// payloads with the documented field numbers. What that verifies is exactly
/// what's easy to get wrong: the field numbering (App ID is 2, creation time is
/// 12, expiration is 21 — not the contiguous run you'd assume), the nested
/// DER-inside-OCTET-STRING encoding, and the metric being a *string*.
final class AppAttestReceiptTests: XCTestCase {

    private let appID = "9GDU5ZNHX7.com.KomodoLLC.SportsCal"

    func test_parsesServerFetchedReceipt() throws {
        let receipt = try AppAttestReceipt(pkcs7: ReceiptBuilder(
            appID: appID,
            receiptType: "RECEIPT",
            creationTime: "2026-08-27T15:44:39.000Z",
            riskMetric: "3",
            notBefore: "2026-08-28T15:44:39.000Z",
            expirationTime: "2026-09-26T15:44:39.000Z"
        ).build())

        XCTAssertEqual(receipt.appID, appID)
        XCTAssertEqual(receipt.receiptType, "RECEIPT")
        XCTAssertEqual(receipt.riskMetric, 3)
        XCTAssertEqual(receipt.attestedPublicKey, Data(ReceiptBuilder.samplePublicKey))
        XCTAssertNotNil(receipt.notBefore)
        XCTAssertNotNil(receipt.expirationTime)
        // Field 12, not field 6 — that's the receipt type.
        XCTAssertEqual(
            ISO8601DateFormatter().string(from: receipt.creationTime),
            "2026-08-27T15:44:39Z"
        )
        // Refresh window ordering must hold, or the refresh scheduling is wrong.
        XCTAssertLessThan(receipt.notBefore!, receipt.expirationTime!)
    }

    func test_attestReceiptHasNoRiskMetric() throws {
        // The receipt bundled in an attestation object is type ATTEST and omits
        // field 17 — the metric only exists after a server round-trip.
        let receipt = try AppAttestReceipt(pkcs7: ReceiptBuilder(
            appID: appID,
            receiptType: "ATTEST",
            creationTime: "2026-08-27T15:44:39.000Z",
            riskMetric: nil,
            notBefore: nil,
            expirationTime: nil
        ).build())

        XCTAssertEqual(receipt.receiptType, "ATTEST")
        XCTAssertNil(receipt.riskMetric)
        XCTAssertNil(receipt.notBefore)
    }

    func test_acceptsTimestampWithoutFractionalSeconds() throws {
        let receipt = try AppAttestReceipt(pkcs7: ReceiptBuilder(
            appID: appID,
            receiptType: "RECEIPT",
            creationTime: "2026-08-27T15:44:39Z",
            riskMetric: "1",
            notBefore: nil,
            expirationTime: nil
        ).build())
        XCTAssertEqual(receipt.riskMetric, 1)
    }

    func test_findsPayloadNestedInsideAContainer() throws {
        // Mirrors the real shape: the field set is buried several levels down in
        // the PKCS #7 structure, so the parser has to walk to it.
        let payload = ReceiptBuilder(
            appID: appID, receiptType: "RECEIPT", creationTime: "2026-08-27T15:44:39.000Z",
            riskMetric: "7", notBefore: nil, expirationTime: nil
        ).build()
        let wrapped = DERWriter.sequence([
            DERWriter.octetString([0xde, 0xad]),          // decoy: not a field set
            DERWriter.sequence([DERWriter.contextConstructed(0, [[UInt8](payload)])])
        ])

        let receipt = try AppAttestReceipt(pkcs7: Data(wrapped))
        XCTAssertEqual(receipt.riskMetric, 7)
        XCTAssertEqual(receipt.appID, appID)
    }

    func test_rejectsPayloadWithoutAppID() {
        // Field 2 is what identifies the payload; without it there is nothing to
        // distinguish the blob from any other octet string in the container.
        let noAppID = ReceiptBuilder(
            appID: nil, receiptType: "RECEIPT", creationTime: "2026-08-27T15:44:39.000Z",
            riskMetric: "1", notBefore: nil, expirationTime: nil
        ).build()
        XCTAssertThrowsError(try AppAttestReceipt(pkcs7: noAppID)) {
            XCTAssertEqual($0 as? AppAttestReceiptError, .payloadNotFound)
        }
    }

    func test_rejectsGarbage() {
        XCTAssertThrowsError(try AppAttestReceipt(pkcs7: Data([0xff, 0xff, 0xff]))) {
            XCTAssertEqual($0 as? AppAttestReceiptError, .malformedContainer)
        }
    }
}

// MARK: - Synthetic receipt construction

/// Builds an OCTET STRING wrapping `SET OF SEQUENCE { type, version, value }`,
/// using Apple's documented field numbers.
private struct ReceiptBuilder {
    let appID: String?
    let receiptType: String
    let creationTime: String
    let riskMetric: String?
    let notBefore: String?
    let expirationTime: String?

    /// Stand-in for the DER SubjectPublicKeyInfo in field 3; the parser treats
    /// it as opaque bytes.
    static let samplePublicKey: [UInt8] = [0x30, 0x03, 0x02, 0x01, 0x07]

    func build() -> Data {
        var entries: [[UInt8]] = []
        func add(_ field: Int, _ value: [UInt8]) {
            entries.append(DERWriter.sequence([
                DERWriter.integer(field),
                DERWriter.integer(1),
                DERWriter.octetString(value)
            ]))
        }
        if let appID { add(2, DERWriter.utf8String(appID)) }
        add(3, Self.samplePublicKey)
        add(6, DERWriter.utf8String(receiptType))
        add(12, DERWriter.utf8String(creationTime))
        if let riskMetric { add(17, DERWriter.utf8String(riskMetric)) }
        if let notBefore { add(19, DERWriter.utf8String(notBefore)) }
        if let expirationTime { add(21, DERWriter.utf8String(expirationTime)) }
        return Data(DERWriter.octetString(DERWriter.set(entries)))
    }
}

/// Just enough DER writing for the fixtures above.
private enum DERWriter {
    static func integer(_ value: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var v = value
        repeat { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 } while v > 0
        // DER integers are signed: a leading high bit needs a zero pad.
        if bytes[0] & 0x80 != 0 { bytes.insert(0, at: 0) }
        return tagged(0x02, bytes)
    }

    static func octetString(_ content: [UInt8]) -> [UInt8] { tagged(0x04, content) }
    static func utf8String(_ s: String) -> [UInt8] { tagged(0x0c, Array(s.utf8)) }
    static func sequence(_ items: [[UInt8]]) -> [UInt8] { tagged(0x30, items.flatMap { $0 }) }
    static func set(_ items: [[UInt8]]) -> [UInt8] { tagged(0x31, items.flatMap { $0 }) }
    static func contextConstructed(_ number: UInt8, _ items: [[UInt8]]) -> [UInt8] {
        tagged(0xa0 | number, items.flatMap { $0 })
    }

    private static func tagged(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    /// Short form under 128, long form above.
    private static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
