@testable import App
import Crypto
import Foundation
import SwiftASN1
import X509

/// Test-only synthesis of App Attest payloads.
///
/// Builds the same structures a real device produces — CBOR attestation object,
/// authenticator data, a certificate chain carrying the nonce extension — but
/// anchored at a throwaway root so tests can exercise the full verification path
/// without a physical device. Every field is a parameter so a test can corrupt
/// exactly one thing.

// MARK: - Attestation

struct AttestationVector {
    let attestation: Data
    let keyID: Data
    let clientDataHash: Data
    let attestedKey: P256.Signing.PrivateKey
    let rootStore: CertificateStore
    let challenge: String

    /// A verifier trusting this vector's throwaway root.
    func verifier(allowDevelopment: Bool = true) -> AppAttestVerifier {
        AppAttestVerifier(
            appID: appID,
            allowDevelopmentEnvironment: allowDevelopment,
            rootCertificates: rootStore
        )
    }

    private let appID: String

    init(
        appID: String,
        challenge: String = "dGVzdC1jaGFsbGVuZ2UtMzItYnl0ZXMtd29ydGgtb2YtZW50cm9weQ==",
        aaguid: [UInt8] = AppAttestVerifier.productionAAGUID,
        signCount: UInt32 = 0,
        format: String = "apple-appattest",
        includeNonceExtension: Bool = true
    ) throws {
        self.appID = appID
        self.challenge = challenge

        // The attested key: the Secure Enclave key a real device would generate.
        let attestedKey = P256.Signing.PrivateKey()
        self.attestedKey = attestedKey
        let keyID = Data(SHA256.hash(data: attestedKey.publicKey.x963Representation))
        self.keyID = keyID

        // The client binds challenge + keyID (see Attestation.swift).
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8) + keyID))
        self.clientDataHash = clientDataHash

        let authData = AuthenticatorDataBuilder.attestation(
            appID: appID,
            aaguid: aaguid,
            signCount: signCount,
            credentialID: [UInt8](keyID),
            publicKey: attestedKey.publicKey
        )

        // Apple embeds SHA256(authData || clientDataHash) in the leaf cert. That
        // is what makes the certificate specific to this challenge.
        let nonce = Data(SHA256.hash(data: authData + clientDataHash))

        let ca = try TestCertificateAuthority()
        self.rootStore = CertificateStore([ca.root])
        let leaf = try ca.issueLeaf(
            publicKey: attestedKey.publicKey,
            nonce: includeNonceExtension ? nonce : nil
        )

        self.attestation = CBOREncoder.map([
            "fmt": .text(format),
            "attStmt": .map([
                "x5c": .array([.bytes(try leaf.derBytes), .bytes(try ca.intermediate.derBytes)]),
                "receipt": .bytes([0x00])   // opaque to us; never parsed
            ]),
            "authData": .bytes([UInt8](authData))
        ])
    }
}

// MARK: - Assertion

enum AssertionVector {
    /// Produces the CBOR `{signature, authenticatorData}` a device returns from
    /// `generateAssertion`.
    static func make(
        key: P256.Signing.PrivateKey,
        appID: String,
        challenge: String,
        counter: UInt32
    ) throws -> Data {
        let authenticatorData = AuthenticatorDataBuilder.assertion(appID: appID, signCount: counter)
        let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))
        // The device signs the nonce; ECDSA applies its own SHA256 on top.
        let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
        let signature = try key.signature(for: nonce)

        return CBOREncoder.map([
            "signature": .bytes([UInt8](signature.derRepresentation)),
            "authenticatorData": .bytes([UInt8](authenticatorData))
        ])
    }
}

// MARK: - Authenticator data

enum AuthenticatorDataBuilder {
    /// Header + attested credential data, as produced during attestation.
    static func attestation(
        appID: String,
        aaguid: [UInt8],
        signCount: UInt32,
        credentialID: [UInt8],
        publicKey: P256.Signing.PublicKey
    ) -> Data {
        var data = header(appID: appID, flags: 0x40, signCount: signCount)   // AT flag set
        data.append(contentsOf: aaguid)
        data.append(UInt8(credentialID.count >> 8))
        data.append(UInt8(credentialID.count & 0xff))
        data.append(contentsOf: credentialID)
        data.append(coseKey(publicKey))
        return data
    }

    /// Header only — assertions carry no credential data.
    static func assertion(appID: String, signCount: UInt32) -> Data {
        header(appID: appID, flags: 0x00, signCount: signCount)
    }

    private static func header(appID: String, flags: UInt8, signCount: UInt32) -> Data {
        var data = Data(SHA256.hash(data: Data(appID.utf8)))
        data.append(flags)
        data.append(UInt8((signCount >> 24) & 0xff))
        data.append(UInt8((signCount >> 16) & 0xff))
        data.append(UInt8((signCount >> 8) & 0xff))
        data.append(UInt8(signCount & 0xff))
        return data
    }

    /// COSE_Key for a P-256 key: {1: 2 (EC2), 3: -7 (ES256), -1: 1 (P-256),
    /// -2: x, -3: y}. The verifier takes the public key from the certificate
    /// rather than here, but real authenticator data always carries it, so the
    /// vectors do too.
    private static func coseKey(_ publicKey: P256.Signing.PublicKey) -> Data {
        let x963 = [UInt8](publicKey.x963Representation)   // 0x04 || X(32) || Y(32)
        let x = Array(x963[1..<33])
        let y = Array(x963[33..<65])
        return CBOREncoder.encode(.intMap([
            1: .int(2), 3: .int(-7), -1: .int(1), -2: .bytes(x), -3: .bytes(y)
        ]))
    }
}

// MARK: - Test certificate authority

/// Root → intermediate → leaf, mirroring Apple's real chain depth.
struct TestCertificateAuthority {
    let root: Certificate
    let intermediate: Certificate

    private let intermediateKey: Certificate.PrivateKey
    private let intermediateName: DistinguishedName

    init() throws {
        let now = Date()
        let notBefore = now.addingTimeInterval(-3600)
        let notAfter = now.addingTimeInterval(86_400)

        let rootKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        let rootName = try DistinguishedName { CommonName("SportsCal Test Attestation Root") }
        root = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: rootKey.publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: rootName,
            subject: rootName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                Critical(KeyUsage(keyCertSign: true))
            },
            issuerPrivateKey: rootKey
        )

        intermediateKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        intermediateName = try DistinguishedName { CommonName("SportsCal Test Attestation CA 1") }
        intermediate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: intermediateKey.publicKey,
            notValidBefore: notBefore,
            notValidAfter: notAfter,
            issuer: rootName,
            subject: intermediateName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true))
            },
            issuerPrivateKey: rootKey
        )
    }

    /// Issues the leaf ("credCert"), optionally carrying the App Attest nonce
    /// extension. Omitting the nonce models a certificate that isn't an
    /// attestation certificate at all.
    func issueLeaf(publicKey: P256.Signing.PublicKey, nonce: Data?) throws -> Certificate {
        let now = Date()
        return try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(publicKey),
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(86_400),
            issuer: intermediateName,
            subject: try DistinguishedName { CommonName("SportsCal Test Attestation Leaf") },
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                if let nonce {
                    Certificate.Extension(
                        oid: AppAttestVerifier.nonceExtensionOID,
                        critical: false,
                        value: ArraySlice(Self.nonceExtensionDER(nonce))
                    )
                }
            },
            issuerPrivateKey: intermediateKey
        )
    }

    /// DER for `SEQUENCE { [1] EXPLICIT { OCTET STRING nonce } }`, hand-encoded
    /// because every length here is fixed and short-form.
    private static func nonceExtensionDER(_ nonce: Data) -> [UInt8] {
        let octetString: [UInt8] = [0x04, UInt8(nonce.count)] + [UInt8](nonce)
        let context: [UInt8] = [0xA1, UInt8(octetString.count)] + octetString
        return [0x30, UInt8(context.count)] + context
    }
}

extension Certificate {
    /// DER bytes, for embedding in the CBOR `x5c` array.
    var derBytes: [UInt8] {
        get throws {
            var serializer = DER.Serializer()
            try serializer.serialize(self)
            return serializer.serializedBytes
        }
    }
}

// MARK: - Minimal CBOR encoder (test-only)

/// Encodes just enough CBOR to build the vectors above. The production code only
/// ever decodes; this is the inverse, and lives in the test target so it can
/// never be mistaken for a supported serialization path.
enum CBORValue {
    case int(Int)
    case bytes([UInt8])
    case text(String)
    case array([CBORValue])
    case map([String: CBORValue])
    case intMap([Int: CBORValue])
}

enum CBOREncoder {
    static func map(_ entries: [String: CBORValue]) -> Data {
        encode(.map(entries))
    }

    static func encode(_ value: CBORValue) -> Data {
        switch value {
        case .int(let v):
            return v >= 0 ? head(0, UInt64(v)) : head(1, UInt64(-1 - v))
        case .bytes(let b):
            return head(2, UInt64(b.count)) + Data(b)
        case .text(let s):
            let utf8 = Array(s.utf8)
            return head(3, UInt64(utf8.count)) + Data(utf8)
        case .array(let items):
            return items.reduce(into: head(4, UInt64(items.count))) { $0 += encode($1) }
        case .map(let entries):
            // Sorted for determinism — CBOR maps are unordered, but a stable
            // encoding makes failing vectors reproducible.
            return entries.keys.sorted().reduce(into: head(5, UInt64(entries.count))) {
                $0 += encode(.text($1)) + encode(entries[$1]!)
            }
        case .intMap(let entries):
            return entries.keys.sorted().reduce(into: head(5, UInt64(entries.count))) {
                $0 += encode(.int($1)) + encode(entries[$1]!)
            }
        }
    }

    /// Major type + argument, using the shortest legal encoding.
    private static func head(_ major: UInt8, _ argument: UInt64) -> Data {
        let prefix = major << 5
        switch argument {
        case 0...23:
            return Data([prefix | UInt8(argument)])
        case 24...0xff:
            return Data([prefix | 24, UInt8(argument)])
        case 0x100...0xffff:
            return Data([prefix | 25, UInt8(argument >> 8), UInt8(argument & 0xff)])
        case 0x10000...0xffff_ffff:
            return Data([prefix | 26] + (0..<4).reversed().map { UInt8((argument >> ($0 * 8)) & 0xff) })
        default:
            return Data([prefix | 27] + (0..<8).reversed().map { UInt8((argument >> ($0 * 8)) & 0xff) })
        }
    }
}
