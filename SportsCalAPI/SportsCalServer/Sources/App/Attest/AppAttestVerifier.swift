import Foundation
import Crypto
import SwiftASN1
import X509

/// Server-side verification of Apple App Attest attestations and assertions.
///
/// Implements "Validating Apps That Connect to Your Server":
/// https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server
///
/// Every check fails closed. There is no bypass flag, no "skip in dev" branch —
/// the only environment-dependent behaviour is which AAGUID we accept, because
/// Xcode-signed builds legitimately attest with the development AAGUID while
/// TestFlight and App Store builds use the production one.
///
/// This type is pure: it takes bytes, returns a verified public key or throws.
/// Redis, challenges, and JWTs live in `AttestController`.
/// Which App Attest environment a client build attested in. Determined by the
/// AAGUID inside the attestation, and the only thing that decides which Apple
/// host will redeem the resulting receipt.
enum AppAttestEnvironment: String, Sendable {
    case production
    case development
}

struct AppAttestVerifier: Sendable {

    /// `<TEAM_ID>.<BUNDLE_ID>` — the App Attest relying-party identifier.
    let appID: String

    /// When true, attestations carrying the *development* AAGUID are accepted
    /// in addition to production ones. Must be false on the prod server: a
    /// development attestation can be produced by any Xcode build signed with
    /// the team's certificate, which is a far weaker claim than a shipped app.
    let allowDevelopmentEnvironment: Bool

    /// Trust anchor(s) the attestation certificate chain must terminate at.
    let rootCertificates: CertificateStore

    /// Injected so tests can validate Apple's sample vectors, whose certificates
    /// expired long ago, at a date when the chain was still valid.
    let validationTime: Date

    init(
        appID: String,
        allowDevelopmentEnvironment: Bool,
        rootCertificates: CertificateStore = AppAttestVerifier.appleRootStore,
        validationTime: Date = Date()
    ) {
        self.appID = appID
        self.allowDevelopmentEnvironment = allowDevelopmentEnvironment
        self.rootCertificates = rootCertificates
        self.validationTime = validationTime
    }

    // MARK: - Constants

    /// OID of the App Attest nonce extension carried in the leaf certificate.
    static let nonceExtensionOID: ASN1ObjectIdentifier = [1, 2, 840, 113635, 100, 8, 2]

    /// AAGUID for apps signed for distribution (App Store / TestFlight).
    static let productionAAGUID: [UInt8] = Array("appattest".utf8) + [0, 0, 0, 0, 0, 0, 0]

    /// AAGUID for Xcode-signed development builds.
    static let developmentAAGUID: [UInt8] = Array("appattestdevelop".utf8)

    // MARK: - Attestation

    /// Verifies a full attestation blob and returns the attested P-256 public
    /// key in X9.63 form, to be stored against the keyID for future assertions.
    ///
    /// - Parameters:
    ///   - attestation: raw CBOR attestation object from `attestKey`.
    ///   - keyID: the 32 raw bytes of the key identifier (base64-decoded).
    ///   - clientDataHash: SHA256 over whatever the client bound to this attest.
    ///     The server computes this itself from the challenge it issued; it is
    ///     never taken from the request body.
    func verifyAttestation(
        attestation: Data,
        keyID: Data,
        clientDataHash: Data
    ) async throws -> Data {
        // 0. keyID is the SHA256 of the public key, so it is always 32 bytes.
        guard keyID.count == 32 else { throw AppAttestError.malformedKeyID }

        // 1. CBOR-decode the attestation object.
        let object = try CBORDecoder.decode(attestation)
        guard object["fmt"]?.text == "apple-appattest" else {
            throw AppAttestError.unexpectedFormat(object["fmt"]?.text ?? "<missing>")
        }
        guard let attStmt = object["attStmt"],
              let x5c = attStmt["x5c"]?.arrayValue, !x5c.isEmpty,
              let authDataBytes = object["authData"]?.bytes else {
            throw AppAttestError.malformedAttestationObject
        }
        let authData = Data(authDataBytes)

        // 2. Parse the certificate chain: x5c[0] is the leaf (credCert), the
        //    remainder are intermediates.
        let chain: [Certificate] = try x5c.map { entry in
            guard let der = entry.bytes else { throw AppAttestError.malformedAttestationObject }
            do { return try Certificate(derEncoded: der) }
            catch { throw AppAttestError.malformedCertificate }
        }
        let leaf = chain[0]
        let intermediates = CertificateStore(chain.dropFirst())

        // 3. Verify the chain terminates at Apple's App Attestation Root CA.
        //    Done before reading anything out of the leaf, so every subsequent
        //    check is reading Apple-signed data rather than attacker-chosen data.
        try await verifyChain(leaf: leaf, intermediates: intermediates)

        // 4. nonce = SHA256(authData || clientDataHash), compared against the
        //    nonce Apple embedded in the leaf certificate. This is the step that
        //    binds the attestation to *our* challenge; without it an attacker
        //    could replay any valid attestation blob.
        let expectedNonce = Data(SHA256.hash(data: authData + clientDataHash))
        let certNonce = try nonce(fromLeaf: leaf)
        guard constantTimeEquals(certNonce, expectedNonce) else {
            throw AppAttestError.nonceMismatch
        }

        // 5. The attested public key lives in the leaf certificate. Its SHA256
        //    must equal the keyID the client claims.
        guard let p256 = P256.Signing.PublicKey(leaf.publicKey) else {
            throw AppAttestError.unexpectedKeyType
        }
        let publicKey = p256.x963Representation
        guard constantTimeEquals(Data(SHA256.hash(data: publicKey)), keyID) else {
            throw AppAttestError.keyIDMismatch
        }

        // 6-8. Structural checks on authenticator data.
        let parsed = try AuthenticatorData(authData)

        guard constantTimeEquals(parsed.rpIDHash, Data(SHA256.hash(data: Data(appID.utf8)))) else {
            throw AppAttestError.rpIDMismatch
        }
        // A freshly generated key has never signed anything.
        guard parsed.signCount == 0 else { throw AppAttestError.nonZeroAttestationCounter }

        guard let credential = parsed.attestedCredential else {
            throw AppAttestError.missingAttestedCredentialData
        }
        guard isAcceptableAAGUID(credential.aaguid) else {
            throw AppAttestError.unexpectedAAGUID(String(decoding: credential.aaguid, as: UTF8.self))
        }
        // The credential ID in authData is the key identifier restated; if it
        // disagrees with the keyID we just matched, the blob is inconsistent.
        guard constantTimeEquals(Data(credential.credentialID), keyID) else {
            throw AppAttestError.credentialIDMismatch
        }

        return publicKey
    }

    /// Pulls the opaque receipt out of an attestation object.
    ///
    /// Kept separate from `verifyAttestation` because the receipt plays no part
    /// in deciding whether an attestation is valid — it is forwarded to Apple
    /// verbatim for the fraud-risk metric. Callers may ignore it entirely.
    static func receipt(fromAttestation attestation: Data) -> Data? {
        guard let object = try? CBORDecoder.decode(attestation),
              let receipt = object["attStmt"]?["receipt"]?.bytes else { return nil }
        return Data(receipt)
    }

    /// Reports which App Attest environment an attestation was minted in, read
    /// from its AAGUID.
    ///
    /// A receipt is only redeemable against the host matching the environment
    /// that produced it, and that environment is a property of the *client
    /// build*, not of the server — a TestFlight build can perfectly well talk to
    /// a staging server. So the receipt host has to follow this, not
    /// `app.environment`.
    ///
    /// Like `receipt(fromAttestation:)`, this is deliberately independent of
    /// verification: it re-reads the blob and makes no validity claim. Callers
    /// must have verified the attestation first.
    static func environment(fromAttestation attestation: Data) -> AppAttestEnvironment? {
        guard let object = try? CBORDecoder.decode(attestation),
              let authData = object["authData"]?.bytes,
              let parsed = try? AuthenticatorData(Data(authData)),
              let credential = parsed.attestedCredential else { return nil }
        if credential.aaguid == Self.productionAAGUID { return .production }
        if credential.aaguid == Self.developmentAAGUID { return .development }
        return nil
    }

    // MARK: - Assertion

    /// Verifies an assertion produced by `generateAssertion` and returns the new
    /// signature counter, which the caller must persist.
    ///
    /// - Parameters:
    ///   - publicKey: X9.63 public key stored at attestation time.
    ///   - clientDataHash: SHA256 of the challenge, computed server-side.
    ///   - previousCounter: last counter we accepted for this key.
    func verifyAssertion(
        assertion: Data,
        publicKey: Data,
        clientDataHash: Data,
        previousCounter: UInt32
    ) throws -> UInt32 {
        let object = try CBORDecoder.decode(assertion)
        guard let signatureBytes = object["signature"]?.bytes,
              let authDataBytes = object["authenticatorData"]?.bytes else {
            throw AppAttestError.malformedAssertion
        }
        let authenticatorData = Data(authDataBytes)

        let key: P256.Signing.PublicKey
        do { key = try P256.Signing.PublicKey(x963Representation: publicKey) }
        catch { throw AppAttestError.unexpectedKeyType }

        let signature: P256.Signing.ECDSASignature
        do { signature = try P256.Signing.ECDSASignature(derRepresentation: Data(signatureBytes)) }
        catch { throw AppAttestError.malformedAssertion }

        // The device signs SHA256(authenticatorData || clientDataHash); CryptoKit
        // applies the outer SHA256 that ECDSA requires.
        let nonce = Data(SHA256.hash(data: authenticatorData + clientDataHash))
        guard key.isValidSignature(signature, for: nonce) else {
            throw AppAttestError.assertionSignatureInvalid
        }

        let parsed = try AuthenticatorData(authenticatorData)
        guard constantTimeEquals(parsed.rpIDHash, Data(SHA256.hash(data: Data(appID.utf8)))) else {
            throw AppAttestError.rpIDMismatch
        }
        // Strictly increasing: the Secure Enclave bumps this on every assertion,
        // so a replayed or reordered assertion lands on <= and is rejected.
        guard parsed.signCount > previousCounter else {
            throw AppAttestError.counterReplay(received: parsed.signCount, stored: previousCounter)
        }

        return parsed.signCount
    }

    // MARK: - Chain verification

    private func verifyChain(leaf: Certificate, intermediates: CertificateStore) async throws {
        var verifier = Verifier(rootCertificates: rootCertificates) {
            RFC5280Policy(validationTime: validationTime)
        }
        let result = await verifier.validate(leafCertificate: leaf, intermediates: intermediates)
        switch result {
        case .validCertificate:
            return
        case .couldNotValidate(let failures):
            throw AppAttestError.certificateChainInvalid(
                failures.map { "\($0.policyFailureReason)" }.joined(separator: "; ")
            )
        }
    }

    // MARK: - Leaf nonce extension

    /// Extracts the 32-byte nonce from the leaf's App Attest extension.
    ///
    /// The extension value is DER `SEQUENCE { [1] EXPLICIT { OCTET STRING } }`.
    /// We walk it explicitly rather than pattern-matching the tail, so a cert
    /// with unexpected structure is an error rather than a silent near-miss.
    private func nonce(fromLeaf leaf: Certificate) throws -> Data {
        guard let ext = leaf.extensions[oid: Self.nonceExtensionOID] else {
            throw AppAttestError.missingNonceExtension
        }
        let parsed = try? DER.parse(ext.value)
        guard let node = parsed else { throw AppAttestError.malformedNonceExtension }

        // SEQUENCE → context-specific [1] → OCTET STRING
        guard case .constructed(let outer) = node.content,
              let contextNode = outer.first(where: {
                  $0.identifier.tagClass == .contextSpecific && $0.identifier.tagNumber == 1
              }),
              case .constructed(let inner) = contextNode.content,
              let octetNode = inner.first(where: {
                  $0.identifier.tagClass == .universal && $0.identifier.tagNumber == 4
              }),
              case .primitive(let raw) = octetNode.content else {
            throw AppAttestError.malformedNonceExtension
        }
        let nonce = Data(raw)
        guard nonce.count == 32 else { throw AppAttestError.malformedNonceExtension }
        return nonce
    }

    private func isAcceptableAAGUID(_ aaguid: [UInt8]) -> Bool {
        if aaguid == Self.productionAAGUID { return true }
        return allowDevelopmentEnvironment && aaguid == Self.developmentAAGUID
    }
}

// MARK: - Authenticator data

/// The fixed-layout header Apple prepends to attestations and assertions.
///
///     0..<32   rpIdHash
///     32       flags
///     33..<37  signCount (big-endian UInt32)
///     [attested credential data, when the AT flag is set]
struct AuthenticatorData {
    let rpIDHash: Data
    let flags: UInt8
    let signCount: UInt32
    let attestedCredential: AttestedCredential?

    struct AttestedCredential {
        let aaguid: [UInt8]        // 16 bytes
        let credentialID: [UInt8]
    }

    /// Set when attested credential data follows the header.
    private static let attestedCredentialDataFlag: UInt8 = 0x40

    init(_ data: Data) throws {
        guard data.count >= 37 else { throw AppAttestError.malformedAuthenticatorData }
        let bytes = [UInt8](data)

        rpIDHash = Data(bytes[0..<32])
        flags = bytes[32]
        signCount = bytes[33..<37].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        guard flags & Self.attestedCredentialDataFlag != 0 else {
            attestedCredential = nil
            return
        }

        // aaguid(16) + credentialIdLength(2) = 18 bytes of fixed header.
        guard bytes.count >= 37 + 18 else { throw AppAttestError.malformedAuthenticatorData }
        let aaguid = Array(bytes[37..<53])
        let idLength = (Int(bytes[53]) << 8) | Int(bytes[54])
        guard idLength > 0, bytes.count >= 55 + idLength else {
            throw AppAttestError.malformedAuthenticatorData
        }
        attestedCredential = AttestedCredential(
            aaguid: aaguid,
            credentialID: Array(bytes[55..<(55 + idLength)])
        )
    }
}

// MARK: - Errors

enum AppAttestError: Error, CustomStringConvertible, Equatable {
    case malformedKeyID
    case unexpectedFormat(String)
    case malformedAttestationObject
    case malformedCertificate
    case certificateChainInvalid(String)
    case missingNonceExtension
    case malformedNonceExtension
    case nonceMismatch
    case unexpectedKeyType
    case keyIDMismatch
    case malformedAuthenticatorData
    case rpIDMismatch
    case nonZeroAttestationCounter
    case missingAttestedCredentialData
    case unexpectedAAGUID(String)
    case credentialIDMismatch
    case malformedAssertion
    case assertionSignatureInvalid
    case counterReplay(received: UInt32, stored: UInt32)

    var description: String {
        switch self {
        case .malformedKeyID:                return "key identifier was not 32 bytes"
        case .unexpectedFormat(let f):       return "attestation fmt was '\(f)', expected 'apple-appattest'"
        case .malformedAttestationObject:    return "attestation object missing required fields"
        case .malformedCertificate:          return "attestation certificate could not be parsed"
        case .certificateChainInvalid(let r): return "certificate chain did not validate: \(r)"
        case .missingNonceExtension:         return "leaf certificate has no App Attest nonce extension"
        case .malformedNonceExtension:       return "App Attest nonce extension was malformed"
        case .nonceMismatch:                 return "attestation nonce did not match the issued challenge"
        case .unexpectedKeyType:             return "attested key was not P-256"
        case .keyIDMismatch:                 return "SHA256 of attested public key did not match keyID"
        case .malformedAuthenticatorData:    return "authenticator data was truncated or malformed"
        case .rpIDMismatch:                  return "relying-party ID hash did not match this app"
        case .nonZeroAttestationCounter:     return "attestation counter was not zero"
        case .missingAttestedCredentialData: return "authenticator data carried no attested credential"
        case .unexpectedAAGUID(let a):       return "unexpected AAGUID '\(a)' for this environment"
        case .credentialIDMismatch:          return "credential ID did not match keyID"
        case .malformedAssertion:            return "assertion object missing required fields"
        case .assertionSignatureInvalid:     return "assertion signature did not verify"
        case .counterReplay(let r, let s):   return "assertion counter \(r) did not advance past \(s)"
        }
    }
}

// MARK: - Constant-time comparison

/// Length-checked, non-short-circuiting compare for the hash/nonce equality
/// checks above. These compare attacker-supplied bytes against server-computed
/// ones, so an early exit would leak how much of a forgery was correct.
func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for (x, y) in zip(a, b) { diff |= x ^ y }
    return diff == 0
}
