import Foundation
import SwiftASN1

/// A parsed App Attest receipt.
///
/// Apple returns these from the attestationData endpoint in a PKCS #7 container
/// whose payload is an ASN.1 `SET OF SEQUENCE { type INTEGER, version INTEGER,
/// value OCTET STRING }`. Field numbers are Apple's, from "Assessing fraud risk":
///
///      2  App ID              12  Creation Time
///      3  Attested Public Key 17  Risk Metric
///      4  Client Hash         19  Not Before
///      5  Token               21  Expiration Time
///      6  Receipt Type
///
/// Note the gaps and the ordering — field 12 is the creation time, not 6, and
/// expiration is 21, not 20. Getting these wrong reads plausible garbage rather
/// than failing, hence the named constants below.
struct AppAttestReceipt {
    /// `<TEAM_ID>.<BUNDLE_ID>` this receipt was issued for.
    let appID: String

    /// DER SubjectPublicKeyInfo of the attested key.
    let attestedPublicKey: Data

    /// `ATTEST` for the receipt inside an attestation object, `RECEIPT` for one
    /// fetched from Apple's server. Only the latter carries a risk metric.
    let receiptType: String

    let creationTime: Date

    /// Approximate count of attested keys this device produced in the last 30
    /// days. Nil on an `ATTEST` receipt. Apple's guidance is to expect a low
    /// number and to tune the threshold against observed traffic — a reinstall,
    /// backup restore, or device transfer legitimately increments it.
    let riskMetric: Int?

    /// Earliest time Apple will honour a refresh. Refreshing before this returns
    /// HTTP 304 rather than a new receipt.
    let notBefore: Date?

    /// After this, Apple may refuse the receipt entirely — refresh before it or
    /// lose the ability to read the metric for this key.
    let expirationTime: Date?

    // MARK: Field numbers

    private enum Field {
        static let appID = 2
        static let attestedPublicKey = 3
        static let receiptType = 6
        static let creationTime = 12
        static let riskMetric = 17
        static let notBefore = 19
        static let expirationTime = 21
    }

    // MARK: - Parsing

    /// Parses the PKCS #7 container Apple returns.
    ///
    /// The PKCS #7 signature is deliberately **not** re-verified here, and that
    /// is safe only because of how this type is used: we parse receipts that
    /// came back from `data.appattest.apple.com` over authenticated TLS, having
    /// been validated by Apple. The client-supplied receipt embedded in an
    /// attestation object is treated as opaque bytes and forwarded, never
    /// parsed — so no untrusted input reaches this code. If that ever changes,
    /// signature and chain verification become mandatory first.
    init(pkcs7 data: Data) throws {
        guard let node = try? DER.parse([UInt8](data)) else {
            throw AppAttestReceiptError.malformedContainer
        }
        guard let fields = Self.findPayload(in: node) else {
            throw AppAttestReceiptError.payloadNotFound
        }

        guard let appID = fields[Field.appID].flatMap(Self.decodeString) else {
            throw AppAttestReceiptError.missingField(Field.appID)
        }
        guard let receiptType = fields[Field.receiptType].flatMap(Self.decodeString) else {
            throw AppAttestReceiptError.missingField(Field.receiptType)
        }
        guard let creationTime = fields[Field.creationTime]
            .flatMap(Self.decodeString).flatMap(Self.decodeDate) else {
            throw AppAttestReceiptError.missingField(Field.creationTime)
        }
        guard let publicKey = fields[Field.attestedPublicKey] else {
            throw AppAttestReceiptError.missingField(Field.attestedPublicKey)
        }

        self.appID = appID
        self.receiptType = receiptType
        self.creationTime = creationTime
        self.attestedPublicKey = Data(publicKey)
        // Apple encodes the metric as a decimal string, not an integer field.
        self.riskMetric = fields[Field.riskMetric].flatMap(Self.decodeString).flatMap { Int($0) }
        self.notBefore = fields[Field.notBefore].flatMap(Self.decodeString).flatMap(Self.decodeDate)
        self.expirationTime = fields[Field.expirationTime]
            .flatMap(Self.decodeString).flatMap(Self.decodeDate)
    }

    /// Walks the DER tree looking for an OCTET STRING whose contents parse as
    /// the receipt payload.
    ///
    /// Rather than navigating PKCS #7 structurally (ContentInfo → SignedData →
    /// encapContentInfo → eContent), we try every octet string and keep the one
    /// that yields a well-formed field set containing the App ID. That is
    /// self-validating: a wrong guess doesn't parse, so it can't silently pick
    /// the wrong blob, and it survives Apple varying the container's shape.
    private static func findPayload(in node: ASN1Node) -> [Int: [UInt8]]? {
        switch node.content {
        case .primitive(let bytes):
            guard node.identifier.tagClass == .universal, node.identifier.tagNumber == 4 else {
                return nil
            }
            guard let fields = try? parseFields(Array(bytes)), fields[Field.appID] != nil else {
                return nil
            }
            return fields
        case .constructed(let children):
            for child in children {
                if let found = findPayload(in: child) { return found }
            }
            return nil
        }
    }

    /// `SET OF SEQUENCE { type INTEGER, version INTEGER, value OCTET STRING }`.
    private static func parseFields(_ bytes: [UInt8]) throws -> [Int: [UInt8]] {
        let node = try DER.parse(bytes)
        guard case .constructed(let entries) = node.content else {
            throw AppAttestReceiptError.malformedPayload
        }
        var fields: [Int: [UInt8]] = [:]
        for entry in entries {
            guard case .constructed(let parts) = entry.content else { continue }
            let items = Array(parts)
            guard items.count >= 3,
                  case .primitive(let typeBytes) = items[0].content,
                  case .primitive(let value) = items[2].content else { continue }
            // Field numbers are small; anything wider is not a field we know.
            let type = typeBytes.reduce(0) { ($0 << 8) | Int($1) }
            // First occurrence wins — Apple emits each field once.
            if fields[type] == nil { fields[type] = Array(value) }
        }
        return fields
    }

    /// Field values are themselves DER objects; the string ones wrap their text
    /// in a UTF8String/IA5String.
    private static func decodeString(_ bytes: [UInt8]) -> String? {
        guard let node = try? DER.parse(bytes),
              case .primitive(let raw) = node.content else { return nil }
        return String(bytes: raw, encoding: .utf8)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Apple emits RFC 3339 with milliseconds ("2026-08-27T15:44:39.000Z"), but
    /// accept the fractionless form too rather than lose a whole receipt to it.
    private static func decodeDate(_ string: String) -> Date? {
        dateFormatter.date(from: string) ?? dateFormatterNoFraction.date(from: string)
    }
}

enum AppAttestReceiptError: Error, CustomStringConvertible, Equatable {
    case malformedContainer
    case payloadNotFound
    case malformedPayload
    case missingField(Int)

    var description: String {
        switch self {
        case .malformedContainer: return "receipt was not a parseable PKCS #7 container"
        case .payloadNotFound:    return "no App Attest receipt payload found in the container"
        case .malformedPayload:   return "receipt payload was not a SET OF field sequences"
        case .missingField(let f): return "receipt is missing required field \(f)"
        }
    }
}
