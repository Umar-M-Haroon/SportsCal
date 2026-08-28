import Foundation
import Vapor
import JWT

/// Talks to Apple's App Attest `attestationData` endpoint to exchange a receipt
/// for a fresh one carrying the device's fraud-risk metric.
///
/// This is the *optional* half of App Attest. Attestation verification itself
/// (`AppAttestVerifier`) is fully offline and needs no Apple credentials — this
/// service exists only to answer "how many attested keys has this device minted
/// lately?", which is the signal against one jailbroken device farming
/// assertions for many clients.
///
/// Everything here is best-effort by design: a failure to reach Apple must never
/// stop a legitimate user from attesting.
struct DeviceCheckClient: Sendable {

    /// DeviceCheck key ID (the `kid` in the auth JWT).
    let keyID: String

    /// Apple Developer team ID (the `iss` claim).
    let teamID: String

    /// The DeviceCheck ES256 private key, PEM-encoded.
    let privateKeyPEM: String

    /// Production talks to `data.appattest.apple.com`; development builds
    /// produce receipts only the sandbox host will accept. A receipt from one
    /// environment is rejected by the other, so this must track the AAGUID
    /// environment the attestation actually used.
    let useProductionEnvironment: Bool

    private var baseURL: String {
        useProductionEnvironment
            ? "https://data.appattest.apple.com/v1/attestationData"
            : "https://data-development.appattest.apple.com/v1/attestationData"
    }

    /// Exchanges a receipt for a refreshed one and parses out the metric.
    ///
    /// - Parameter receipt: the raw receipt bytes — from the attestation object
    ///   the first time, then the most recently returned receipt on refreshes.
    /// - Returns: the new receipt, both raw (store it for the next refresh) and
    ///   parsed. `nil` when Apple answers 304, meaning we asked again before the
    ///   previous receipt's "not before" date.
    func fetchReceipt(_ receipt: Data, on client: Client, logger: Logger) async throws
        -> (raw: Data, parsed: AppAttestReceipt)? {

        let token = try authenticationToken()

        // The body is the base64 receipt as text, and the header carries the raw
        // JWT with NO "Bearer " prefix — unlike almost every other Apple API.
        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: token)
        headers.add(name: .contentType, value: "text/plain")

        let response = try await client.post(URI(string: baseURL), headers: headers) { request in
            request.body = ByteBuffer(string: receipt.base64EncodedString())
        }

        switch response.status.code {
        case 200:
            guard var body = response.body,
                  let base64 = body.readString(length: body.readableBytes),
                  let der = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                throw DeviceCheckError.malformedResponse
            }
            return (der, try AppAttestReceipt(pkcs7: der))
        case 304:
            // Asked too early. Not an error — the caller should keep the receipt
            // it has and try again after its notBefore date.
            logger.debug("attestationData: 304, refreshed before the not-before date")
            return nil
        default:
            throw DeviceCheckError.unexpectedStatus(Int(response.status.code))
        }
    }

    /// Builds the ES256 provider token Apple expects — the same shape as an APNs
    /// provider authentication token: header `{alg, kid}`, claims `{iss, iat}`.
    private func authenticationToken() throws -> String {
        let signers = JWTSigners()
        do {
            try signers.use(.es256(key: ECDSAKey.private(pem: privateKeyPEM)), kid: JWKIdentifier(string: keyID))
        } catch {
            throw DeviceCheckError.invalidPrivateKey
        }
        struct ProviderToken: JWTPayload {
            let iss: String
            let iat: Int
            func verify(using signer: JWTSigner) throws {}
        }
        return try signers.sign(
            ProviderToken(iss: teamID, iat: Int(Date().timeIntervalSince1970)),
            kid: JWKIdentifier(string: keyID)
        )
    }
}

enum DeviceCheckError: Error, CustomStringConvertible {
    case invalidPrivateKey
    case malformedResponse
    case unexpectedStatus(Int)

    var description: String {
        switch self {
        case .invalidPrivateKey:      return "DeviceCheck private key could not be loaded as an ES256 PEM"
        case .malformedResponse:      return "attestationData response was not a base64 receipt"
        case .unexpectedStatus(401):  return "attestationData rejected the auth token (401) — check DEVICECHECK_KEY_ID / TeamID / key"
        case .unexpectedStatus(let c): return "attestationData returned HTTP \(c)"
        }
    }
}
