@testable import App
import Crypto
import Foundation
import SwiftASN1
import X509
import XCTest

/// End-to-end tests for App Attest verification.
///
/// Apple does not publish attestation test vectors, and a real blob can only be
/// produced on a physical device. So these tests synthesize the whole structure
/// — root CA, leaf certificate with the nonce extension, authenticator data,
/// CBOR envelope — against a *test* trust anchor injected through
/// `AppAttestVerifier(rootCertificates:)`. That covers every check the verifier
/// makes except "the anchor is genuinely Apple's", which is a compile-time
/// constant (see AppleAppAttestRoot.swift) and is asserted separately below.
///
/// Each negative test mutates exactly one field of an otherwise-valid vector, so
/// a failure names the specific check that stopped working.
final class AppAttestVerifierTests: XCTestCase {

    private let appID = "9GDU5ZNHX7.com.KomodoLLC.SportsCal"

    // MARK: - Attestation: happy path

    func test_validAttestation_returnsAttestedPublicKey() async throws {
        let vector = try AttestationVector(appID: appID)
        let publicKey = try await vector.verifier().verifyAttestation(
            attestation: vector.attestation,
            keyID: vector.keyID,
            clientDataHash: vector.clientDataHash
        )
        XCTAssertEqual(publicKey, vector.attestedKey.publicKey.x963Representation)
        // The returned key is what gets stored and later used for assertions,
        // so it must round-trip through the storage representation.
        XCTAssertNoThrow(try P256.Signing.PublicKey(x963Representation: publicKey))
    }

    // MARK: - Attestation: rejections

    func test_rejectsWrongChallenge() async throws {
        let vector = try AttestationVector(appID: appID)
        // Same blob, different challenge — the nonce baked into the certificate
        // no longer matches. This is the check that stops attestation replay.
        await XCTAssertThrowsAppAttestError(.nonceMismatch) {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: Data(SHA256.hash(data: Data("a different challenge".utf8)))
            )
        }
    }

    func test_rejectsChainNotAnchoredAtExpectedRoot() async throws {
        let vector = try AttestationVector(appID: appID)
        // Verify the same attestation against the real Apple root. A chain the
        // attacker minted themselves must not validate.
        let appleAnchored = AppAttestVerifier(
            appID: appID,
            allowDevelopmentEnvironment: true,
            rootCertificates: AppAttestVerifier.appleRootStore
        )
        await XCTAssertThrowsAppAttestError { error in
            guard case .certificateChainInvalid = error else {
                return XCTFail("expected certificateChainInvalid, got \(error)")
            }
        } operation: {
            try await appleAnchored.verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsKeyIDThatIsNotHashOfAttestedKey() async throws {
        let vector = try AttestationVector(appID: appID)
        var forgedKeyID = vector.keyID
        forgedKeyID[0] ^= 0xff
        await XCTAssertThrowsAppAttestError(.keyIDMismatch) {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: forgedKeyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsAttestationForAnotherApp() async throws {
        let vector = try AttestationVector(appID: "9GDU5ZNHX7.com.someone.else")
        // Verifier configured for *our* app ID; the blob attests a different one.
        let ours = AppAttestVerifier(
            appID: appID,
            allowDevelopmentEnvironment: true,
            rootCertificates: vector.rootStore
        )
        await XCTAssertThrowsAppAttestError(.rpIDMismatch) {
            try await ours.verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsNonZeroCounterOnAttestation() async throws {
        let vector = try AttestationVector(appID: appID, signCount: 1)
        await XCTAssertThrowsAppAttestError(.nonZeroAttestationCounter) {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsDevelopmentAAGUID_whenDevelopmentDisallowed() async throws {
        let vector = try AttestationVector(
            appID: appID,
            aaguid: AppAttestVerifier.developmentAAGUID
        )
        // A development attestation is producible by any Xcode build signed with
        // the team certificate — production must not accept it.
        let production = AppAttestVerifier(
            appID: appID,
            allowDevelopmentEnvironment: false,
            rootCertificates: vector.rootStore
        )
        await XCTAssertThrowsAppAttestError { error in
            guard case .unexpectedAAGUID = error else {
                return XCTFail("expected unexpectedAAGUID, got \(error)")
            }
        } operation: {
            try await production.verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_acceptsDevelopmentAAGUID_whenDevelopmentAllowed() async throws {
        let vector = try AttestationVector(
            appID: appID,
            aaguid: AppAttestVerifier.developmentAAGUID
        )
        let development = AppAttestVerifier(
            appID: appID,
            allowDevelopmentEnvironment: true,
            rootCertificates: vector.rootStore
        )
        // Xcode-signed builds must still work against a dev server.
        _ = try await development.verifyAttestation(
            attestation: vector.attestation,
            keyID: vector.keyID,
            clientDataHash: vector.clientDataHash
        )
    }

    func test_rejectsUnknownAAGUID_evenInDevelopment() async throws {
        let vector = try AttestationVector(
            appID: appID,
            aaguid: Array("notappattest0000".utf8)
        )
        await XCTAssertThrowsAppAttestError { error in
            guard case .unexpectedAAGUID = error else {
                return XCTFail("expected unexpectedAAGUID, got \(error)")
            }
        } operation: {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsWrongFormat() async throws {
        let vector = try AttestationVector(appID: appID, format: "android-key")
        await XCTAssertThrowsAppAttestError { error in
            guard case .unexpectedFormat = error else {
                return XCTFail("expected unexpectedFormat, got \(error)")
            }
        } operation: {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsMissingNonceExtension() async throws {
        let vector = try AttestationVector(appID: appID, includeNonceExtension: false)
        await XCTAssertThrowsAppAttestError(.missingNonceExtension) {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsShortKeyID() async throws {
        let vector = try AttestationVector(appID: appID)
        await XCTAssertThrowsAppAttestError(.malformedKeyID) {
            try await vector.verifier().verifyAttestation(
                attestation: vector.attestation,
                keyID: Data([1, 2, 3]),
                clientDataHash: vector.clientDataHash
            )
        }
    }

    func test_rejectsGarbageAttestation() async throws {
        let vector = try AttestationVector(appID: appID)
        do {
            _ = try await vector.verifier().verifyAttestation(
                attestation: Data([0xde, 0xad, 0xbe, 0xef]),
                keyID: vector.keyID,
                clientDataHash: vector.clientDataHash
            )
            XCTFail("expected garbage attestation to be rejected")
        } catch {
            // Either a CBOR failure or a structural one — both are fail-closed.
            XCTAssertTrue(error is CBORError || error is AppAttestError, "unexpected \(error)")
        }
    }

    // MARK: - Assertion

    func test_validAssertion_returnsNewCounter() throws {
        let key = P256.Signing.PrivateKey()
        let challenge = "challenge-1"
        let assertion = try AssertionVector.make(key: key, appID: appID, challenge: challenge, counter: 7)

        let counter = try verifier().verifyAssertion(
            assertion: assertion,
            publicKey: key.publicKey.x963Representation,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))),
            previousCounter: 6
        )
        XCTAssertEqual(counter, 7)
    }

    func test_rejectsAssertionSignedByAnotherKey() throws {
        let challenge = "challenge-1"
        let assertion = try AssertionVector.make(
            key: P256.Signing.PrivateKey(), appID: appID, challenge: challenge, counter: 1
        )
        // Right structure, wrong signer.
        XCTAssertThrowsError(try verifier().verifyAssertion(
            assertion: assertion,
            publicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))),
            previousCounter: 0
        )) { XCTAssertEqual($0 as? AppAttestError, .assertionSignatureInvalid) }
    }

    func test_rejectsAssertionForAnotherChallenge() throws {
        let key = P256.Signing.PrivateKey()
        let assertion = try AssertionVector.make(key: key, appID: appID, challenge: "issued", counter: 1)
        // The signature covers the challenge, so a substituted one fails the
        // signature check rather than sneaking through.
        XCTAssertThrowsError(try verifier().verifyAssertion(
            assertion: assertion,
            publicKey: key.publicKey.x963Representation,
            clientDataHash: Data(SHA256.hash(data: Data("substituted".utf8))),
            previousCounter: 0
        )) { XCTAssertEqual($0 as? AppAttestError, .assertionSignatureInvalid) }
    }

    func test_rejectsReplayedCounter() throws {
        let key = P256.Signing.PrivateKey()
        let challenge = "challenge-1"
        let assertion = try AssertionVector.make(key: key, appID: appID, challenge: challenge, counter: 5)
        // Counter must strictly advance: a resubmitted assertion at the stored
        // counter is a replay.
        XCTAssertThrowsError(try verifier().verifyAssertion(
            assertion: assertion,
            publicKey: key.publicKey.x963Representation,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))),
            previousCounter: 5
        )) { XCTAssertEqual($0 as? AppAttestError, .counterReplay(received: 5, stored: 5)) }
    }

    func test_rejectsRewoundCounter() throws {
        let key = P256.Signing.PrivateKey()
        let challenge = "challenge-1"
        let assertion = try AssertionVector.make(key: key, appID: appID, challenge: challenge, counter: 3)
        XCTAssertThrowsError(try verifier().verifyAssertion(
            assertion: assertion,
            publicKey: key.publicKey.x963Representation,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))),
            previousCounter: 9
        )) { XCTAssertEqual($0 as? AppAttestError, .counterReplay(received: 3, stored: 9)) }
    }

    func test_rejectsAssertionForAnotherApp() throws {
        let key = P256.Signing.PrivateKey()
        let challenge = "challenge-1"
        let assertion = try AssertionVector.make(
            key: key, appID: "9GDU5ZNHX7.com.someone.else", challenge: challenge, counter: 1
        )
        XCTAssertThrowsError(try verifier().verifyAssertion(
            assertion: assertion,
            publicKey: key.publicKey.x963Representation,
            clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))),
            previousCounter: 0
        )) { XCTAssertEqual($0 as? AppAttestError, .rpIDMismatch) }
    }

    func test_rejectsMalformedAssertion() throws {
        XCTAssertThrowsError(try verifier().verifyAssertion(
            assertion: Data([0xde, 0xad]),
            publicKey: P256.Signing.PrivateKey().publicKey.x963Representation,
            clientDataHash: Data(),
            previousCounter: 0
        ))
    }

    // MARK: - Trust anchor

    func test_embeddedAppleRootIsTheExpectedCertificate() throws {
        // Guards against an accidental edit to the pinned PEM. Fingerprint from
        // https://www.apple.com/certificateauthority/private/
        let root = try Certificate(pemEncoded: AppAttestVerifier.appleRootCAPEM)
        XCTAssertEqual("\(root.subject)", "ST=California,O=Apple Inc.,CN=Apple App Attestation Root CA")
        let der = try { () -> [UInt8] in
            var serializer = DER.Serializer()
            try serializer.serialize(root)
            return serializer.serializedBytes
        }()
        let fingerprint = SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
        XCTAssertEqual(
            fingerprint,
            "1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32"
        )
    }

    // MARK: - Helpers

    private func verifier() -> AppAttestVerifier {
        AppAttestVerifier(appID: appID, allowDevelopmentEnvironment: true)
    }

    /// Async-aware assertion helper — XCTAssertThrowsError doesn't accept an
    /// async autoclosure.
    private func XCTAssertThrowsAppAttestError(
        _ expected: AppAttestError,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        await XCTAssertThrowsAppAttestError(
            { XCTAssertEqual($0, expected, file: file, line: line) },
            operation: operation, file: file, line: line
        )
    }

    private func XCTAssertThrowsAppAttestError(
        _ check: (AppAttestError) -> Void,
        operation: () async throws -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("expected an AppAttestError but none was thrown", file: file, line: line)
        } catch let error as AppAttestError {
            check(error)
        } catch {
            XCTFail("expected an AppAttestError, got \(error)", file: file, line: line)
        }
    }
}
